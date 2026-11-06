import 'dart:math';

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

/// Everything the server does for this game: hold a room, list who is in it,
/// and record who was caught when. The rules all run on the phones.
class RoomRepository {
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
  Future<Room> joinRoom({
    required String code,
    required String deviceId,
    required String name,
  }) async {
    final rows = await _db.from('rooms').select().eq('code', code).limit(1);
    if (rows.isEmpty) {
      throw const RoomUnavailable('No table with that code.');
    }

    await _db.from('room_players').upsert({
      'room_code': code,
      'device_id': deviceId,
      'name': name,
    }, onConflict: 'room_code,device_id');

    return Room.fromRow(rows.first);
  }

  Stream<Room?> watchRoom(String code) {
    return _db
        .from('rooms')
        .stream(primaryKey: ['code'])
        .eq('code', code)
        .map((rows) => rows.isEmpty ? null : Room.fromRow(rows.first));
  }

  Stream<List<RoomPlayer>> watchPlayers(String code) {
    return _db
        .from('room_players')
        .stream(primaryKey: ['id'])
        .eq('room_code', code)
        .map((rows) => rows.map(RoomPlayer.fromRow).toList());
  }

  /// Host only: moves everyone to the next phase.
  Future<void> setStatus(String code, RoomStatus status) async {
    await _db.from('rooms').update({
      'status': status.name,
      if (status == RoomStatus.settling)
        'started_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('code', code);
  }

  /// Clears every player's catch so the same table can play again.
  Future<void> resetRound(String code) async {
    await _db.from('room_players').update({
      'caught_at': null,
      'lasted_ms': null,
      'catch_reason': null,
    }).eq('room_code', code);
  }

  /// This phone was caught. Written once — a later report must never overwrite
  /// an earlier one, or the loser could change after the fact.
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

final roomRepositoryProvider = Provider<RoomRepository>((_) => RoomRepository());
