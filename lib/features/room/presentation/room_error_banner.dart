import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/room_session.dart';

/// Shows whatever went wrong with the table.
///
/// Room errors used to be rendered only on the join and host screens, so a
/// realtime failure mid-round — the moment it matters most — told the player
/// nothing at all and the board simply stopped updating.
class RoomErrorBanner extends ConsumerWidget {
  const RoomErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(roomSessionProvider).error;
    if (error == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 18, color: AppTheme.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Colors.white54,
            onPressed: () =>
                ref.read(roomSessionProvider.notifier).dismissError(),
          ),
        ],
      ),
    );
  }
}
