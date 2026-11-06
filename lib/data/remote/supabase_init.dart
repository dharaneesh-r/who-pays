import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';

/// True once Supabase is up. Rooms are optional: if this fails — no network at
/// the restaurant, project paused, bad key — solo play must still work, so
/// nothing here is allowed to throw into the app's startup path.
bool supabaseReady = false;

Future<void> initSupabase() async {
  if (!SupabaseConfig.isConfigured) return;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
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
