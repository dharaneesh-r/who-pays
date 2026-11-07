import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/duel/domain/duel_models.dart';
import 'room_repository.dart' show RoomUnavailable;
import 'supabase_init.dart';

/// What a duel needs from the server, so tests can supply a fake.
abstract interface class DuelRepo {
  Future<Duel> createDuel({required String name});
  Future<Duel> findDuel(String code);
  Stream<List<DuelScore>> watchToday(String code);
  Future<List<DuelScore>> todayScores(String code);
  Future<Map<String, int>> wins(String code);
  Future<void> submit({
    required String code,
    required String deviceId,
    required String name,
    required Duration best,
  });
}

class DuelRepository implements DuelRepo {
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I or O
  static const _codeLength = 4;
  static const _maxAttempts = 8;

  final _random = Random.secure();

  SupabaseClient get _db {
    if (!supabaseReady) {
      throw const RoomUnavailable('Not connected — try again on wifi.');
    }
    return supabase;
  }

  String _newCode() => List.generate(
        _codeLength,
        (_) => _alphabet[_random.nextInt(_alphabet.length)],
      ).join();

  /// Today in the player's own timezone. The duel is "who lasted longest
  /// today", and today has to mean their day, not UTC's.
  static String todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<Duel> createDuel({required String name}) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final code = _newCode();
      try {
        final row = await _db
            .from('duels')
            .insert({'code': code, 'name': name})
            .select()
            .single();
        return Duel.fromRow(row);
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow; // not a code collision
      }
    }
    throw const RoomUnavailable('Could not create a duel. Try again.');
  }

  @override
  Future<Duel> findDuel(String code) async {
    final rows = await _db.from('duels').select().eq('code', code).limit(1);
    if (rows.isEmpty) throw const RoomUnavailable('No duel with that code.');
    return Duel.fromRow(rows.first);
  }

  @override
  Stream<List<DuelScore>> watchToday(String code) {
    final today = todayKey();
    return _db
        .from('duel_scores')
        .stream(primaryKey: ['id'])
        .eq('duel_code', code)
        .map((rows) => rows
            .where((r) => r['day'] == today)
            .map(DuelScore.fromRow)
            .toList());
  }

  @override
  Future<List<DuelScore>> todayScores(String code) async {
    final rows = await _db
        .from('duel_today')
        .select()
        .eq('duel_code', code)
        .eq('day', todayKey());
    return rows.map(DuelScore.fromRow).toList();
  }

  @override
  Future<Map<String, int>> wins(String code) async {
    final rows = await _db.from('duel_wins').select().eq('duel_code', code);
    return {
      for (final r in rows) r['device_id'] as String: r['days_won'] as int,
    };
  }

  /// Records a round, keeping only the day's best.
  ///
  /// Upsert then compare rather than read-then-write: two rounds finishing
  /// close together could otherwise both read the old best and the better one
  /// lose.
  @override
  Future<void> submit({
    required String code,
    required String deviceId,
    required String name,
    required Duration best,
  }) async {
    final day = todayKey();
    final ms = best.inMilliseconds;

    final existing = await _db
        .from('duel_scores')
        .select('best_ms')
        .eq('duel_code', code)
        .eq('device_id', deviceId)
        .eq('day', day)
        .limit(1);

    if (existing.isNotEmpty && (existing.first['best_ms'] as int) >= ms) {
      return; // already have a better round today
    }

    await _db.from('duel_scores').upsert({
      'duel_code': code,
      'device_id': deviceId,
      'name': name,
      'day': day,
      'best_ms': ms,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'duel_code,device_id,day');

    // Keeps the duel from being swept up as abandoned.
    await _db
        .from('duels')
        .update({'last_used': DateTime.now().toUtc().toIso8601String()})
        .eq('code', code);
  }
}

final duelRepositoryProvider = Provider<DuelRepo>((_) => DuelRepository());
