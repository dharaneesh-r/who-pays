import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/device_identity.dart';
import 'supabase_init.dart';

/// Anonymous product analytics.
///
/// Records what the app does, never who did it: the only identifier is the
/// random device UUID, which is tied to nothing and dies with an uninstall.
/// No names, no stakes text, no prompts, no room codes.
///
/// Every call is fire-and-forget and swallows errors. Analytics failing must
/// never be something a player can notice.
class AnalyticsService {
  AnalyticsService(this._identity);

  final DeviceIdentity _identity;

  static const _firstOpenKey = 'analytics_first_open_sent';

  /// Dropped rather than queued when offline. A restaurant with bad wifi is
  /// the normal case for this app, and a growing retry queue would cost more
  /// than the data is worth.
  Future<void> log(String event, [Map<String, dynamic>? props]) async {
    if (!supabaseReady) return;
    try {
      await supabase.from('app_events').insert({
        'device_id': await _identity.id(),
        'event': event,
        'props': props ?? const <String, dynamic>{},
        'platform': defaultTargetPlatform.name,
      });
    } catch (_) {/* analytics must never surface to the player */}
  }

  /// Called once per install. `first_open` is as close to an install count as
  /// the app itself can get — Play Console remains the real source.
  Future<void> appOpened() async {
    unawaited(log('app_open'));
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_firstOpenKey) ?? false) return;
      await prefs.setBool(_firstOpenKey, true);
      unawaited(log('first_open'));
    } catch (_) {}
  }

  void roundStarted({required bool inRoom}) =>
      unawaited(log('round_started', {'in_room': inRoom}));

  void roundFinished({
    required String outcome,
    String? reason,
    required int lastedMs,
    required bool inRoom,
  }) =>
      unawaited(log('round_finished', {
        'outcome': outcome,
        'reason': ?reason,
        'lasted_ms': lastedMs,
        'in_room': inRoom,
      }));

  void roomCreated() => unawaited(log('room_created'));
  void roomJoined() => unawaited(log('room_joined'));
  void packSelected(String pack) => unawaited(log('pack_selected', {'pack': pack}));
  void resultShared() => unawaited(log('result_shared'));
  void adShown() => unawaited(log('ad_shown'));
}

final analyticsProvider = Provider<AnalyticsService>(
  (ref) => AnalyticsService(ref.watch(deviceIdentityProvider)),
);
