import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import 'app.dart';
import 'data/remote/analytics_service.dart';
import 'data/remote/supabase_init.dart';
import 'features/paywall/application/ads_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Rooms are optional. If this fails the app still plays solo, so startup
  // never waits on, or fails because of, the network.
  await initSupabase();

  // The game lives on a table — the phone is always portrait and face down.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  final container = ProviderContainer();
  // Warm the ad up front so the first result screen is not the one that waits.
  unawaited(container.read(adsServiceProvider).init());
  unawaited(container.read(analyticsProvider).appOpened());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WhoPaysApp(),
    ),
  );
}
