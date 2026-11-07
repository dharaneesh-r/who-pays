import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';

/// True once Supabase is up. Rooms are optional: if this fails — no network at
/// the restaurant, project paused, bad key — solo play must still work, so
/// nothing here is allowed to throw into the app's startup path.
bool supabaseReady = false;

Future<void> initSupabase({String? deviceId}) async {
  if (!SupabaseConfig.isConfigured) return;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
      // Declares which phone this is on every request. The row-level security
      // policies only allow a client to change rows carrying this id, which
      // is what stops anyone with the publishable key from deleting other
      // people's tables — table codes are four letters and trivially guessed,
      // device ids are random UUIDs and are not.
      //
      // It is not authentication: the header can be set to anything. It
      // raises the cost of mischief from "guess a code" to "already know
      // someone's device id", which is the right trade for a game with no
      // accounts.
      headers: {
        if (deviceId != null && deviceId.isNotEmpty) 'x-device-id': deviceId,
      },
      // No accounts in this app — a four-letter code shared at one table is
      // the only thing that identifies a room.
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    supabaseReady = true;
  } catch (_) {
    supabaseReady = false;
  }
}

SupabaseClient get supabase => Supabase.instance.client;

final supabaseReadyProvider = Provider<bool>((_) => supabaseReady);
