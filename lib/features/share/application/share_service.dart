import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../game/domain/game_models.dart';
import '../../room/domain/room_models.dart';
import '../presentation/result_card.dart';

/// Renders the result card off-screen and hands it to the share sheet.
///
/// Rendering off-screen rather than screenshotting the live result screen
/// keeps the shared image at a fixed, readable size regardless of the phone it
/// was played on.
class ShareService {
  final _controller = ScreenshotController();

  Future<void> shareResult({
    required GameConfig config,
    required RoundResult result,
    String? loserName,
    List<RoomPlayer> standings = const [],
  }) async {
    final bytes = await _render(
      config: config,
      result: result,
      loserName: loserName,
      standings: standings,
    );
    if (bytes == null) return;

    final file = await _writeTempPng(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: loserName != null
            ? '$loserName ${config.stakeText}. 😤'
            : 'Phones down. First to crack pays.',
      ),
    );
  }

  Future<Uint8List?> _render({
    required GameConfig config,
    required RoundResult result,
    String? loserName,
    List<RoomPlayer> standings = const [],
  }) async {
    try {
      return await _controller.captureFromWidget(
        ResultCard(
          config: config,
          result: result,
          loserName: loserName,
          standings: standings,
        ),
        targetSize: const Size(ResultCard.width, ResultCard.height),
        delay: const Duration(milliseconds: 40),
      );
    } catch (_) {
      // Sharing is a nice-to-have; never let it break the end of a round.
      return null;
    }
  }

  Future<File> _writeTempPng(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, 'who-pays-${DateTime.now().millisecondsSinceEpoch}.png'),
    );
    return file.writeAsBytes(bytes);
  }
}

final shareServiceProvider = Provider<ShareService>((_) => ShareService());
