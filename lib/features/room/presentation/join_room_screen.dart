import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/local/prefs_service.dart';
import '../application/room_session.dart';
import 'room_lobby_screen.dart';
import 'scan_qr_screen.dart';

class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  static const path = '/join';

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _nameLoaded = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Scanning fills the code in rather than joining straight away, so the
  /// player can still fix their name before committing.
  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanQrScreen()),
    );
    if (code == null || !mounted) return;
    _code.text = code;
    await _submit();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref.read(prefsServiceProvider).setPlayerName(_name.text);
    await ref.read(roomSessionProvider.notifier).join(_code.text);

    if (!mounted) return;
    if (ref.read(roomSessionProvider).inRoom) {
      context.pushReplacement(RoomLobbyScreen.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(roomSessionProvider);

    // Prefill the name once, without fighting the user's cursor afterwards.
    ref.watch(playerNameProvider).whenData((name) {
      if (!_nameLoaded) {
        _nameLoaded = true;
        if (name != PrefsService.defaultPlayerName) _name.text = name;
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Join a table')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  hintText: 'What the table calls you',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                maxLength: 4,
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 12,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                  TextInputFormatter.withFunction(
                    (_, next) => next.copyWith(text: next.text.toUpperCase()),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Table code',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (session.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  session.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: session.joining ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('SCAN THE QR'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: session.joining ? null : _submit,
                child: Text(session.joining ? 'JOINING…' : 'JOIN'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
