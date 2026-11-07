import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small per-viewer settings. Anything that must survive a reinstall or be
/// shared with the group belongs in the database, not here.
class PrefsService {
  static const _playerNameKey = 'player_name';
  static const _sirenKey = 'siren_enabled';
  static const _lastRoomKey = 'last_room_code';
  static const _remindersKey = 'reminders_enabled';

  static const defaultPlayerName = 'You';

  Future<String> playerName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_playerNameKey)?.trim();
    return (stored == null || stored.isEmpty) ? defaultPlayerName : stored;
  }

  /// True once the player has chosen a name. Until then solo rounds are saved
  /// as "You", which makes the group leaderboard meaningless.
  Future<bool> hasPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_playerNameKey)?.trim().isNotEmpty) ?? false;
  }

  Future<void> setPlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = name.trim();
    if (clean.isEmpty) {
      await prefs.remove(_playerNameKey);
    } else {
      await prefs.setString(_playerNameKey, clean);
    }
  }

  /// The evening streak nudge. On by default — it is the only thing that
  /// brings anyone back on a day nobody organised a dinner.
  Future<bool> remindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_remindersKey) ?? true;
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_remindersKey, enabled);
  }

  /// The table this phone was last at, so a player whose app was killed can
  /// be offered a way back instead of having to ask for the code again.
  Future<String?> lastRoomCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRoomKey);
  }

  Future<void> setLastRoomCode(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_lastRoomKey);
    } else {
      await prefs.setString(_lastRoomKey, code);
    }
  }

  /// The siren can be silenced for a library, a hospital, a sleeping baby.
  /// Vibration still fires — muting everything would remove the only thing
  /// that enforces the game.
  Future<bool> sirenEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sirenKey) ?? true;
  }

  Future<void> setSirenEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sirenKey, enabled);
  }
}

final prefsServiceProvider = Provider<PrefsService>((_) => PrefsService());

final playerNameProvider = FutureProvider<String>(
  (ref) => ref.watch(prefsServiceProvider).playerName(),
);

final hasPlayerNameProvider = FutureProvider<bool>(
  (ref) => ref.watch(prefsServiceProvider).hasPlayerName(),
);

final sirenEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(prefsServiceProvider).sirenEnabled(),
);

final remindersEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(prefsServiceProvider).remindersEnabled(),
);
