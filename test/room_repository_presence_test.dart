import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:who_pays/data/remote/room_repository.dart';

/// The app has to keep working against a database that has not had the
/// presence migration applied. Getting this predicate wrong is not a cosmetic
/// bug: too narrow and nobody can join a table at all, too wide and a real
/// error gets swallowed and retried forever.
void main() {
  PostgrestException err(String code, String message) =>
      PostgrestException(message: message, code: code);

  group('isMissingPresenceColumn', () {
    test('recognises the write-side answer (schema cache)', () {
      expect(
        RoomRepository.isMissingPresenceColumn(err(
          'PGRST204',
          "Could not find the 'last_seen' column of 'room_players' in the schema cache",
        )),
        isTrue,
      );
    });

    test('recognises the read-side answer (Postgres itself)', () {
      expect(
        RoomRepository.isMissingPresenceColumn(
          err('42703', 'column room_players.last_seen does not exist'),
        ),
        isTrue,
      );
    });

    test('does not swallow a different missing column', () {
      expect(
        RoomRepository.isMissingPresenceColumn(
          err('42703', 'column room_players.nickname does not exist'),
        ),
        isFalse,
      );
    });

    test('does not swallow unrelated failures', () {
      expect(
        RoomRepository.isMissingPresenceColumn(
          err('23503', 'insert violates foreign key constraint'),
        ),
        isFalse,
      );
      expect(
        RoomRepository.isMissingPresenceColumn(
          err('42501', 'new row violates row-level security policy'),
        ),
        isFalse,
      );
    });

    test('ignores errors that are not Postgrest errors at all', () {
      expect(
        RoomRepository.isMissingPresenceColumn(
          Exception('last_seen'),
        ),
        isFalse,
      );
    });
  });
}
