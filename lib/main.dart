import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/remote/supabase_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Rooms are optional. If this fails the app still plays solo, so startup
  // never waits on, or fails because of, the network.
  await initSupabase();

  // The game lives on a table — the phone is always portrait and face down.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const ProviderScope(child: WhoPaysApp()));
}
