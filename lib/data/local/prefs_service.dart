import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small per-viewer settings. Anything that must survive a reinstall or be
/// shared with the group belongs in the database, not here.
class PrefsService {
  static const _playerNameKey = 'player_name';
  static const _sirenKey = 'siren_enabled';

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
