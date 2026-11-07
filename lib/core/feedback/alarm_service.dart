import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/local/prefs_service.dart';

/// Sound, vibration and keeping the screen awake.
///
/// The siren is not decoration — it is the entire enforcement mechanism. The
/// app cannot stop anyone touching their phone; it can only make sure the whole
/// table knows instantly. So it has to be loud, immediate, and awkward.
class AlarmService {
  AlarmService(this._prefs);

  final PrefsService _prefs;
  final _player = AudioPlayer(playerId: 'siren');

  bool _sirenReady = false;
  bool _firing = false;

  /// Loads the siren so the first catch is not delayed by disk I/O.
  Future<void> warmUp() async {
    if (_sirenReady) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setSource(AssetSource('audio/siren.wav'));
      await _player.setVolume(1);
      _sirenReady = true;
    } catch (_) {
      // Audio is best-effort: a device with no usable audio output must still
      // be able to play the game.
      _sirenReady = false;
    }
  }

  /// Someone was caught. Siren + a long insistent vibration pattern.
  Future<void> fire() async {
    if (_firing) return;
    _firing = true;

    try {
      // Silenced for a library or a sleeping baby. The vibration below still
      // fires, so the player is still caught.
      if (await _prefs.sirenEnabled()) {
        await warmUp();
        if (_sirenReady) await _player.resume();
      }
    } catch (_) {/* keep going — the vibration still works */}

    try {
      if (await Vibration.hasVibrator()) {
        // Long-short-long, repeating: reads as an alarm rather than a notification.
        await Vibration.vibrate(
          pattern: [0, 600, 200, 300, 200, 600],
          repeat: 0,
        );
      } else {
        await HapticFeedback.heavyImpact();
      }
    } catch (_) {/* no haptics on this device */}
  }

  /// Stop the noise — the group has acknowledged the loser.
  Future<void> silence() async {
    _firing = false;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }

  /// A light tap for ordinary UI confirmations.
  Future<void> tick() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// The timer must stay visible without anyone touching the phone — which is
  /// the one thing the game forbids.
  Future<void> keepAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await silence();
    await keepAwake(false);
    await _player.dispose();
  }
}

final alarmServiceProvider = Provider<AlarmService>((ref) {
  final service = AlarmService(ref.watch(prefsServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});
