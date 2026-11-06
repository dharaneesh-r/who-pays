import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/join_link.dart';
import '../../game/presentation/game_screen.dart';
import '../application/room_session.dart';
import '../domain/room_models.dart';

/// Where the table gathers before a round. The code is the biggest thing on
/// screen because it gets read aloud across a noisy restaurant.
class RoomLobbyScreen extends ConsumerWidget {
  const RoomLobbyScreen({super.key});

  static const path = '/room';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(roomSessionProvider);
    final controller = ref.read(roomSessionProvider.notifier);
    final text = Theme.of(context).textTheme;

    // The host has started the round — everyone's phone follows.
    ref.listen(roomSessionProvider, (_, next) {
      final status = next.snapshot?.room.status;
      if (status == RoomStatus.settling || status == RoomStatus.running) {
        if (GoRouterState.of(context).uri.path == RoomLobbyScreen.path) {
          context.push(GameScreen.path);
        }
      }
    });

    final snapshot = session.snapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your table'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            await controller.leave();
            if (context.mounted && context.canPop()) context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: session.joining || snapshot == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Everyone opens the app and types',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: Colors.white60),
                    ),
                    const SizedBox(height: 10),
                    _CodeCard(code: snapshot.room.code),
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: JoinLink.forCode(snapshot.room.code),
                          size: 132,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '…or scan this',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: Colors.white38),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'At the table (${snapshot.players.length})',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final player in snapshot.players)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person, size: 20),
                              title: Text(player.name),
                              trailing: snapshot.room.isHost(player.deviceId)
                                  ? const Text(
                                      'HOST',
                                      style: TextStyle(
                                        color: AppTheme.accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      'Loser ${snapshot.room.config.stakeText}',
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    if (session.isHost)
                      FilledButton(
                        onPressed: snapshot.players.length < 2
                            ? null
                            : controller.startRound,
                        child: Text(
                          snapshot.players.length < 2
                              ? 'WAITING FOR PLAYERS…'
                              : 'PHONES DOWN',
                        ),
                      )
                    else
                      Text(
                        'Waiting for the host to start…',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: Colors.white54),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code copied')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          border: Border.all(color: AppTheme.accent, width: 2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          code,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            letterSpacing: 14,
            color: AppTheme.accent,
          ),
        ),
      ),
    );
  }
}
