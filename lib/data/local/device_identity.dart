import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A stable id for this phone.
///
/// Used to recognise a returning player so rejoining a room after the app is
/// killed does not create a duplicate. Random, local, and tied to nothing
/// about the person — there are no accounts in this app.
class DeviceIdentity {
  static const _key = 'device_id';

  Future<String> id() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final fresh = const Uuid().v4();
    await prefs.setString(_key, fresh);
    return fresh;
  }
}

final deviceIdentityProvider = Provider<DeviceIdentity>((_) => DeviceIdentity());

final deviceIdProvider =
    FutureProvider<String>((ref) => ref.watch(deviceIdentityProvider).id());
