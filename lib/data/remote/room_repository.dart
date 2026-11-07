import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/detector/domain/detector_models.dart';
import '../../features/game/domain/game_models.dart';
import '../../features/room/domain/room_models.dart';
import 'supabase_init.dart';

class RoomUnavailable implements Exception {
  const RoomUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a room needs from the server, so tests can supply a fake one.
abstract interface class RoomRepo {
  Future<Room> createRoom({
    required String deviceId,
    required String name,
    required GameConfig config,
  });
  Future<Room> joinRoom({
    required String code,
    required String deviceId,
    required String name,
  });
  Stream<Room?> watchRoom(String code);
  Stream<List<RoomPlayer>> watchPlayers(String code);
  Future<void> touch({required String code, required String deviceId});
  Future<bool> roomExists(String code);
  Future<void> setStatus(String code, RoomStatus status);
  Future<void> resetRound(String code);
  Future<void> reportCaught({
    required String code,
    required String deviceId,
    required Duration lasted,
    required CatchReason reason,
  });
  Future<void> leaveRoom({required String code, required String deviceId});
}

/// Everything the server does for this game: hold a room, list who is in it,
/// and record who was caught when. The rules all run on the phones.
class RoomRepository implements RoomRepo {
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I or O
  static const _codeLength = 4;
  static const _maxCodeAttempts = 8;

  final _random = Random.secure();

  SupabaseClient get _db {
    if (!supabaseReady) {
      throw const RoomUnavailable('Not connected — you can still play solo.');
    }
    return supabase;
  }

  String _newCode() => List.generate(
        _codeLength,
        (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)],
      ).join();

  /// Creates a room and puts the host in it.
  ///
  /// Codes are short enough to read aloud across a table, which means
  /// collisions are possible — so insert, and on a clash try another code.
  @override
  Future<Room> createRoom({
    required String deviceId,
    required String name,
    required GameConfig config,
  }) async {
    for (var attempt = 0; attempt < _maxCodeAttempts; attempt++) {
      final code = _newCode();
      try {
        final row = await _db.from('rooms').insert({
          'code': code,
          'host_id': deviceId,
          'stake': config.stake.name,
          'custom_stake': config.customStake,
          'target_ms': config.target?.inMilliseconds,
          'status': RoomStatus.lobby.name,
        }).select().single();

        await joinRoom(code: code, deviceId: deviceId, name: name);
        return Room.fromRow(row);
      } on PostgrestException catch (e) {
        // 23505 = unique violation: that code is taken, pick another.
        if (e.code != '23505') rethrow;
      }
    }
    throw const RoomUnavailable('Could not create a room. Try again.');
  }

  /// Joins, or rejoins after the app was killed — the same device keeps its row.
  /// Whether this database has the presence column.
  ///
  /// It is a deployment fact, not a code fact: an app build can reach a
  /// database that has not had the presence migration applied yet. Sending
  /// `last_seen` to such a database makes PostgREST reject the entire
  /// request, which took joining a table from "presence is a bit stale" to
  /// "nobody can join at all". Losing the whole feature because one optional
  /// column is missing is never the right trade.
  ///
  /// Starts optimistic and latches off the first time the server says the
  /// column is unknown, so the cost is one failed request per app run.
  bool _presenceSupported = true;

  /// True when this error means "that column does not exist here".
  ///
  /// PostgREST answers in two different ways depending on whether it is
  /// writing (its own schema cache, PGRST204) or reading (Postgres itself,
  /// 42703), and both mean the same thing to us.
  @visibleForTesting
  static bool isMissingPresenceColumn(Object e) =>
      e is PostgrestException &&
      (e.code == 'PGRST204' || e.code == '42703') &&
      (e.message.contains('last_seen'));

  @override
  Future<Room> joinRoom({
    required String code,
    required String deviceId,
    required String name,
  }) async {
    final rows = await _db.from('rooms').select().eq('code', code).limit(1);
    if (rows.isEmpty) {
      throw const RoomUnavailable('No table with that code.');
    }

    Map<String, dynamic> row() => {
          'room_code': code,
          'device_id': deviceId,
          'name': name,
          if (_presenceSupported)
            'last_seen': DateTime.now().toUtc().toIso8601String(),
        };

    try {
      await _db
          .from('room_players')
          .upsert(row(), onConflict: 'room_code,device_id');
    } on PostgrestException catch (e) {
      if (!isMissingPresenceColumn(e)) rethrow;
      _presenceSupported = false;
      // Retry without it: being at the table matters more than knowing
      // exactly when someone was last seen.
      await _db
          .from('room_players')
          .upsert(row(), onConflict: 'room_code,device_id');
    }

    return Room.fromRow(rows.first);
  }

  @override
  Stream<Room?> watchRoom(String code) {
    return _db
        .from('rooms')
        .stream(primaryKey: ['code'])
        .eq('code', code)
        .map((rows) => rows.isEmpty ? null : Room.fromRow(rows.first));
  }

  @override
  Stream<List<RoomPlayer>> watchPlayers(String code) {
    return _db
        .from('room_players')
        .stream(primaryKey: ['id'])
        .eq('room_code', code)
        .map((rows) => rows.map(RoomPlayer.fromRow).toList());
  }

  /// "I am still here." Sent on a timer while in a room; a phone that stops
  /// sending it is treated as having left the table.
  @override
  Future<void> touch({
    required String code,
    required String deviceId,
  }) async {
    if (!_presenceSupported) return;
    try {
      await _db
          .from('room_players')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('room_code', code)
          .eq('device_id', deviceId);
    } on PostgrestException catch (e) {
      if (!isMissingPresenceColumn(e)) rethrow;
      // Stop beating against a database that cannot record it. Everyone
      // stays listed as present, which is how the app behaved before
      // presence existed.
      _presenceSupported = false;
    }
  }

  /// Does this room still exist? Used to decide whether a saved code is worth
  /// offering as a rejoin.
  @override
  Future<bool> roomExists(String code) async {
    try {
      final rows = await _db.from('rooms').select('code').eq('code', code).limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Host only: moves everyone to the next phase.
  @override
  Future<void> setStatus(String code, RoomStatus status) async {
    await _db.from('rooms').update({
      'status': status.name,
      if (status == RoomStatus.settling)
        'started_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('code', code);
  }

  /// Clears every player's catch so the same table can play again.
  ///
  /// Goes through a definer function rather than a direct update, because
  /// this is the one write that legitimately touches other people's rows.
  /// The function checks the caller really is the host of this room; letting
  /// the policy allow it instead would let anyone wipe anyone's results.
  @override
  Future<void> resetRound(String code) async {
    try {
      await _db.rpc('reset_round', params: {'p_code': code});
    } on PostgrestException catch (e) {
      // PGRST202: the function is not there, so this database has not had
      // the lockdown migration yet. Under the old blanket policy the direct
      // update still works, and an app build must not be able to break
      // "play again" on a database that simply has not caught up.
      if (e.code != 'PGRST202') rethrow;
      await _db.from('room_players').update({
        'caught_at': null,
        'lasted_ms': null,
        'catch_reason': null,
      }).eq('room_code', code);
    }
  }

  /// This phone was caught. Written once — a later report must never overwrite
  /// an earlier one, or the loser could change after the fact.
  @override
  Future<void> reportCaught({
    required String code,
    required String deviceId,
    required Duration lasted,
    required CatchReason reason,
  }) async {
    await _db
        .from('room_players')
        .update({
          'caught_at': DateTime.now().toUtc().toIso8601String(),
          'lasted_ms': lasted.inMilliseconds,
          'catch_reason': reason.name,
        })
        .eq('room_code', code)
        .eq('device_id', deviceId)
        .isFilter('caught_at', null);
  }

  @override
  Future<void> leaveRoom({
    required String code,
    required String deviceId,
  }) async {
    await _db
        .from('room_players')
        .delete()
        .eq('room_code', code)
        .eq('device_id', deviceId);
  }
}

final roomRepositoryProvider = Provider<RoomRepo>((_) => RoomRepository());
