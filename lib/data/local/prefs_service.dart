import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small per-viewer settings. Anything that must survive a reinstall or be
/// shared with the group belongs in the database, not here.
class PrefsService {
  static const _playerNameKey = 'player_name';
  static const defaultPlayerName = 'You';

  Future<String> playerName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_playerNameKey)?.trim();
    return (stored == null || stored.isEmpty) ? defaultPlayerName : stored;
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
}

final prefsServiceProvider = Provider<PrefsService>((_) => PrefsService());

final playerNameProvider = FutureProvider<String>(
  (ref) => ref.watch(prefsServiceProvider).playerName(),
);
