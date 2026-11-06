import 'dart:convert';
import 'dart:math';

/// A set of conversation prompts.
///
/// Punishing phone use leaves a hole — *now what do we talk about?* These fill
/// it, and they are the difference between a one-time party trick and
/// something a group does every Friday.
class CardPack {
  const CardPack({
    required this.id,
    required this.name,
    required this.free,
    required this.prompts,
  });

  final String id;
  final String name;

  /// Paid packs are the cleanest in-app purchase in the app: they cost
  /// almost nothing to make and never go stale.
  final bool free;
  final List<String> prompts;

  static CardPack fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return CardPack(
      id: map['id'] as String,
      name: map['name'] as String,
      free: map['free'] as bool? ?? false,
      prompts: (map['prompts'] as List<dynamic>).cast<String>(),
    );
  }
}

/// Serves prompts one at a time, in a shuffled order that does not repeat
/// until the pack is exhausted.
///
/// A plain random pick feels broken at a table, because the same question
/// reappearing twice in ten minutes is immediately noticed.
class PromptDeck {
  PromptDeck(this.prompts, {int? seed}) : _random = Random(seed) {
    _reshuffle();
  }

  final List<String> prompts;
  final Random _random;

  List<String> _order = const [];
  int _index = 0;

  bool get isEmpty => prompts.isEmpty;

  String? get current => isEmpty ? null : _order[_index];

  String? next() {
    if (isEmpty) return null;
    _index++;
    if (_index >= _order.length) {
      _reshuffle();
      _index = 0;
    }
    return current;
  }

  void _reshuffle() {
    if (prompts.isEmpty) {
      _order = const [];
      return;
    }
    final shuffled = [...prompts]..shuffle(_random);
    // Avoid repeating the prompt that was just on screen across a reshuffle.
    if (_order.isNotEmpty && shuffled.length > 1 && shuffled.first == _order.last) {
      final moved = shuffled.removeAt(0);
      shuffled.add(moved);
    }
    _order = shuffled;
  }
}
