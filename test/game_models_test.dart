import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/game/domain/game_models.dart';

void main() {
  group('formatClock', () {
    test('shows mm:ss below an hour', () {
      expect(formatClock(Duration.zero), '00:00');
      expect(formatClock(const Duration(seconds: 7)), '00:07');
      expect(formatClock(const Duration(minutes: 7, seconds: 3)), '07:03');
      expect(formatClock(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('adds hours only when the round runs that long', () {
      expect(formatClock(const Duration(hours: 1)), '1:00:00');
      expect(
        formatClock(const Duration(hours: 2, minutes: 5, seconds: 9)),
        '2:05:09',
      );
    });
  });

  group('GameConfig', () {
    test('a custom stake falls back to a sane phrase when left blank', () {
      const blank = GameConfig(stake: Stake.custom, customStake: '   ');
      expect(blank.stakeText, 'loses');

      const set = GameConfig(stake: Stake.custom, customStake: ' walks the dog ');
      expect(set.stakeText, 'walks the dog');
    });

    test('clearTarget makes the round open-ended', () {
      const config = GameConfig(target: Duration(minutes: 30));
      expect(config.copyWith(clearTarget: true).target, isNull);
    });

    test('copyWith keeps the target when not clearing it', () {
      const config = GameConfig(target: Duration(minutes: 30));
      expect(config.copyWith(stake: Stake.dishes).target,
          const Duration(minutes: 30));
    });
  });

  group('GameState.targetProgress', () {
    test('is null for an open-ended round', () {
      const state = GameState(config: GameConfig(target: null));
      expect(state.targetProgress, isNull);
    });

    test('tracks elapsed against the target', () {
      const state = GameState(
        config: GameConfig(target: Duration(minutes: 10)),
        elapsed: Duration(minutes: 5),
      );
      expect(state.targetProgress, closeTo(0.5, 0.001));
    });

    test('clamps past the target rather than overflowing the bar', () {
      const state = GameState(
        config: GameConfig(target: Duration(minutes: 10)),
        elapsed: Duration(minutes: 30),
      );
      expect(state.targetProgress, 1.0);
    });
  });
}
