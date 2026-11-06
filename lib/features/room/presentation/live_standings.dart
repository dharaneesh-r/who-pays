import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../game/domain/game_models.dart';
import '../application/room_session.dart';

/// The live board during a round. Shown only when sitting at a table — a solo
/// round has nobody to compare against.
class LiveStandings extends ConsumerWidget {
  const LiveStandings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(roomSessionProvider);
    final snapshot = session.snapshot;
    if (snapshot == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final player in snapshot.standings)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  player.isOut ? Icons.close_rounded : Icons.circle,
                  size: player.isOut ? 18 : 10,
                  color: player.isOut ? AppTheme.danger : AppTheme.safe,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    player.deviceId == session.deviceId
                        ? '${player.name}  (you)'
                        : player.name,
                    style: TextStyle(
                      color: player.isOut ? Colors.white38 : Colors.white,
                      fontWeight:
                          player.isOut ? FontWeight.w400 : FontWeight.w700,
                      decoration:
                          player.isOut ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (player.isOut && player.lasted != null)
                  Text(
                    formatClock(player.lasted!),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
