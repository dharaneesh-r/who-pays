import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../game/domain/game_models.dart';
import '../../room/domain/room_models.dart';

/// The image that gets posted in the WhatsApp group.
///
/// This is the growth loop, so it is built to be read at thumbnail size in a
/// busy chat: one big claim, the names, and the app's name at the bottom.
/// Fixed size rather than responsive — it is rendered off-screen to a PNG, not
/// laid out on a phone.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.config,
    required this.result,
    this.loserName,
    this.standings = const [],
  });

  final GameConfig config;
  final RoundResult result;
  final String? loserName;
  final List<RoomPlayer> standings;

  static const width = 1080.0;
  static const height = 1080.0;

  @override
  Widget build(BuildContext context) {
    final headline = loserName != null
        ? '$loserName\n${config.stakeText}'
        : (result.outcome == RoundOutcome.caught
            ? 'CAUGHT\nafter ${formatClock(result.lasted)}'
            : 'NOBODY CRACKED\n${formatClock(result.lasted)}');

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(72),
        color: AppTheme.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PHONES DOWN',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
            const Spacer(),
            Text(
              headline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 96,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(height: 48),
            if (standings.isNotEmpty)
              ...standings.take(6).map(
                    (player) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Icon(
                            player.isOut
                                ? Icons.close_rounded
                                : Icons.check_rounded,
                            size: 36,
                            color: player.isOut
                                ? AppTheme.danger
                                : AppTheme.safe,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Text(
                              player.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 38,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (player.lasted != null)
                            Text(
                              formatClock(player.lasted!),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 36,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            const Spacer(),
            const Text(
              'Who Pays?  ·  first to touch their phone loses',
              style: TextStyle(color: Colors.white38, fontSize: 30),
            ),
          ],
        ),
      ),
    );
  }
}
