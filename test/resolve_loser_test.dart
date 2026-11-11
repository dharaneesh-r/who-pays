import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/bill/domain/resolve_loser.dart';

void main() {
  group('alone', () {
    test('being caught is losing — the bug this function exists for', () {
      // Found on a real phone: the player was caught, the siren went off, the
      // result screen said "So you pay the bill", and the split screen then
      // said nobody had cracked and divided the bill evenly.
      expect(
        resolveLoser(
          roomLoser: null,
          inRoom: false,
          caught: true,
          myName: 'Asha',
        ),
        'Asha',
      );
    });

    test('falls back to "You" when no name is saved', () {
      // Must match what the participant list uses, or the loser would not be
      // found among the participants and nobody would be charged.
      expect(
        resolveLoser(
          roomLoser: null,
          inRoom: false,
          caught: true,
          myName: null,
        ),
        'You',
      );
    });

    test('surviving the round means nobody lost', () {
      expect(
        resolveLoser(
          roomLoser: null,
          inRoom: false,
          caught: false,
          myName: 'Asha',
        ),
        isNull,
      );
    });
  });

  group('at a table', () {
    test('the room decides, not this phone', () {
      expect(
        resolveLoser(
          roomLoser: 'Bala',
          inRoom: true,
          caught: true,
          myName: 'Asha',
        ),
        'Bala',
      );
    });

    test('being caught does not mean losing — someone may have been faster',
        () {
      // The loser is whoever cracked *first*. This phone cracking says
      // nothing about whether it was first, which is exactly why rule 1 does
      // not fall through to the solo rule.
      expect(
        resolveLoser(
          roomLoser: null,
          inRoom: true,
          caught: true,
          myName: 'Asha',
        ),
        isNull,
      );
    });

    test('a survivor at a table still sees who lost', () {
      expect(
        resolveLoser(
          roomLoser: 'Bala',
          inRoom: true,
          caught: false,
          myName: 'Asha',
        ),
        'Bala',
      );
    });
  });
}
