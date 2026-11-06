import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../game/presentation/setup_view.dart';
import '../application/room_session.dart';
import 'room_lobby_screen.dart';

/// Hosting is the same two choices as a solo round — they just end up in a
/// room instead of starting immediately.
class HostSetupScreen extends ConsumerWidget {
  const HostSetupScreen({super.key});

  static const path = '/host';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(roomSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Host a table')),
      body: SafeArea(
        child: Column(
          children: [
            if (session.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  session.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Expanded(
              child: SetupView(
                actionLabel: session.joining ? 'CREATING…' : 'CREATE THE TABLE',
                onStart: (config) async {
                  await ref.read(roomSessionProvider.notifier).host(config);
                  if (!context.mounted) return;
                  if (ref.read(roomSessionProvider).inRoom) {
                    context.pushReplacement(RoomLobbyScreen.path);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
