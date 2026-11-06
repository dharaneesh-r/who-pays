import '../../detector/domain/detector_models.dart';

/// What the loser owes. The stake is the whole reason anyone plays, so it is
/// chosen before the round and shown on every screen.
enum Stake { bill, nextRound, dishes, chores, custom }

extension StakeLabel on Stake {
  String get label => switch (this) {
        Stake.bill => 'pays the bill',
        Stake.nextRound => 'buys the next round',
        Stake.dishes => 'does the dishes',
        Stake.chores => 'does the chores',
        Stake.custom => 'loses',
      };

  String get short => switch (this) {
        Stake.bill => 'Bill',
        Stake.nextRound => 'Next round',
        Stake.dishes => 'Dishes',
        Stake.chores => 'Chores',
        Stake.custom => 'Custom',
      };
}

/// Phases of one round on this phone.
enum RoundPhase {
  /// Choosing the stake and the length.
  setup,

  /// Phones are going down; waiting for this one to be still.
  settling,

  /// Armed and counting. Do not touch.
  running,

  /// Either caught, or the target time was reached.
  finished,
}

class GameConfig {
  const GameConfig({
    this.stake = Stake.bill,
    this.customStake,
    this.target = const Duration(minutes: 30),
  });

  final Stake stake;
  final String? customStake;

  /// Null means open-ended: play until someone cracks.
  final Duration? target;

  String get stakeText => stake == Stake.custom
      ? (customStake?.trim().isNotEmpty == true ? customStake!.trim() : 'loses')
      : stake.label;

  GameConfig copyWith({
    Stake? stake,
    String? customStake,
    Duration? target,
    bool clearTarget = false,
  }) {
    return GameConfig(
      stake: stake ?? this.stake,
      customStake: customStake ?? this.customStake,
      target: clearTarget ? null : (target ?? this.target),
    );
  }
}

/// How a finished round ended.
enum RoundOutcome { caught, survived }

class RoundResult {
  const RoundResult({
    required this.outcome,
    required this.lasted,
    this.reason,
  });

  final RoundOutcome outcome;
  final Duration lasted;

  /// Only set when [outcome] is [RoundOutcome.caught].
  final CatchReason? reason;
}

class GameState {
  const GameState({
    this.phase = RoundPhase.setup,
    this.config = const GameConfig(),
    this.elapsed = Duration.zero,
    this.detector = const DetectorSnapshot.idle(),
    this.result,
  });

  final RoundPhase phase;
  final GameConfig config;

  /// Time since the round armed — what the player is trying to maximise.
  final Duration elapsed;

  final DetectorSnapshot detector;
  final RoundResult? result;

  /// Progress toward the target, or null when open-ended.
  double? get targetProgress {
    final target = config.target;
    if (target == null || target == Duration.zero) return null;
    return (elapsed.inMilliseconds / target.inMilliseconds).clamp(0.0, 1.0);
  }

  GameState copyWith({
    RoundPhase? phase,
    GameConfig? config,
    Duration? elapsed,
    DetectorSnapshot? detector,
    RoundResult? result,
    bool clearResult = false,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      config: config ?? this.config,
      elapsed: elapsed ?? this.elapsed,
      detector: detector ?? this.detector,
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

/// mm:ss for the big clock. Hours are shown only if a round really runs that
/// long, so the common case stays as wide as possible on screen.
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
