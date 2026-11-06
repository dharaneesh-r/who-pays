import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/cards/domain/card_pack.dart';

void main() {
  group('CardPack.fromJson', () {
    test('reads a pack', () {
      final pack = CardPack.fromJson('''
        {"id":"friends","name":"Friends","free":true,
         "prompts":["one","two"]}
      ''');

      expect(pack.id, 'friends');
      expect(pack.name, 'Friends');
      expect(pack.free, isTrue);
      expect(pack.prompts, ['one', 'two']);
    });

    test('treats a pack without the free flag as paid', () {
      final pack = CardPack.fromJson(
        '{"id":"deep","name":"Deep Talk","prompts":["x"]}',
      );
      expect(pack.free, isFalse);
    });
  });

  group('PromptDeck', () {
    test('an empty deck shows nothing rather than crashing', () {
      final deck = PromptDeck([]);
      expect(deck.isEmpty, isTrue);
      expect(deck.current, isNull);
      expect(deck.next(), isNull);
    });

    test('a single prompt just repeats', () {
      final deck = PromptDeck(['only'], seed: 1);
      expect(deck.current, 'only');
      expect(deck.next(), 'only');
    });

    test('shows every prompt before repeating any', () {
      final prompts = List.generate(8, (i) => 'q$i');
      final deck = PromptDeck(prompts, seed: 42);

      final seen = <String>{deck.current!};
      for (var i = 0; i < prompts.length - 1; i++) {
        seen.add(deck.next()!);
      }

      expect(seen.length, prompts.length,
          reason: 'a repeat inside one pass is immediately noticed at a table');
    });

    test('does not repeat the same prompt across a reshuffle', () {
      // Every seed must hold this, so check a spread of them.
      for (var seed = 0; seed < 25; seed++) {
        final prompts = List.generate(4, (i) => 'q$i');
        final deck = PromptDeck(prompts, seed: seed);

        for (var i = 0; i < prompts.length - 1; i++) {
          deck.next();
        }
        final last = deck.current;
        final afterReshuffle = deck.next();

        expect(afterReshuffle, isNot(last),
            reason: 'seed $seed repeated "$last" across the wrap');
      }
    });

    test('keeps cycling indefinitely', () {
      final deck = PromptDeck(['a', 'b', 'c'], seed: 7);
      for (var i = 0; i < 100; i++) {
        expect(deck.next(), isNotNull);
      }
    });
  });
}
