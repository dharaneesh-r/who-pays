import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/bill/domain/participant_seed.dart';

void main() {
  /// Convenience: the common starting point, nothing seeded, nothing edited.
  List<String>? seed(
    List<String> candidate, {
    required bool fromTable,
    bool alreadySeeded = false,
    bool alreadySeededFromTable = false,
    bool edited = false,
  }) {
    return seedParticipants(
      candidate: candidate,
      fromTable: fromTable,
      alreadySeeded: alreadySeeded,
      alreadySeededFromTable: alreadySeededFromTable,
      edited: edited,
    );
  }

  test('seeds from nothing', () {
    expect(seed(['Asha'], fromTable: false), ['Asha']);
    expect(seed(['Asha', 'Bala'], fromTable: true), ['Asha', 'Bala']);
  });

  test('an empty list is not an answer', () {
    // Both sources are empty on the first frame; neither should latch.
    expect(seed([], fromTable: false), isNull);
    expect(seed([], fromTable: true), isNull);
  });

  group('the bug this function exists for', () {
    test('a late table list replaces the solo fallback', () {
      // The real failure: the saved name arrives first, the room snapshot a
      // frame later. Seeding once meant the split stayed at one person and
      // the rest of the table was told they owed nothing.
      expect(
        seed(
          ['Asha', 'Bala', 'Chitra', 'Dev'],
          fromTable: true,
          alreadySeeded: true,
          alreadySeededFromTable: false,
        ),
        ['Asha', 'Bala', 'Chitra', 'Dev'],
      );
    });

    test('the solo fallback never replaces a table list', () {
      expect(
        seed(
          ['Asha'],
          fromTable: false,
          alreadySeeded: true,
          alreadySeededFromTable: true,
        ),
        isNull,
      );
    });

    test('the solo fallback does not replace itself', () {
      // Otherwise every rebuild would reset a list the user may have added to
      // before the flag was set.
      expect(
        seed(['Asha'], fromTable: false, alreadySeeded: true),
        isNull,
      );
    });

    test('the table list is only accepted once', () {
      // A heartbeat re-emits the player list constantly. Accepting it twice
      // would undo a reorder, or re-add somebody who had just been removed.
      expect(
        seed(
          ['Asha', 'Bala'],
          fromTable: true,
          alreadySeeded: true,
          alreadySeededFromTable: true,
        ),
        isNull,
      );
    });
  });

  group('once the user has touched it, the list is theirs', () {
    test('an edit blocks the table list', () {
      expect(
        seed(['Asha', 'Bala'], fromTable: true, edited: true),
        isNull,
      );
    });

    test('an edit blocks the solo fallback', () {
      expect(seed(['Asha'], fromTable: false, edited: true), isNull);
    });

    test('an edit before anything seeded still wins', () {
      // Someone who types a name in before the room snapshot lands must not
      // have it wiped a moment later.
      expect(
        seed(
          ['Asha', 'Bala'],
          fromTable: true,
          alreadySeeded: false,
          edited: true,
        ),
        isNull,
      );
    });
  });
}
