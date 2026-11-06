/// The phase of a single phone within a round.
enum DetectorState {
  /// Not watching. Between rounds.
  idle,

  /// The phone has been put down but has not been still long enough yet.
  /// The game cannot start while anyone is still fidgeting.
  settling,

  /// Flat, still, and being watched. Pick it up and you are caught.
  armed,

  /// This phone was picked up.
  caught,
}

/// Why a player was caught. Shown on the result screen, and logged so a group
/// can argue about it.
enum CatchReason {
  /// Linear acceleration sustained past the threshold — lifted off the table.
  motion,

  /// Rotation sustained past the threshold — tilted or flipped over.
  rotation,

  /// They left the app. On a phone that is face down, this means they picked
  /// it up, unlocked it and switched away.
  leftApp,

  /// The screen was unlocked while the round was running.
  screenUnlocked,

  /// The player tapped "I give up", or the host called it.
  conceded,
}

extension CatchReasonLabel on CatchReason {
  String get label => switch (this) {
        CatchReason.motion => 'Picked the phone up',
        CatchReason.rotation => 'Turned the phone over',
        CatchReason.leftApp => 'Left the app',
        CatchReason.screenUnlocked => 'Unlocked the screen',
        CatchReason.conceded => 'Gave up',
      };
}

/// An immutable read-out of the detector. Drives both the game UI and the dev
/// screen, so every number that matters is here rather than hidden in the
/// detector's private fields.
class DetectorSnapshot {
  const DetectorSnapshot({
    required this.state,
    required this.linearAcceleration,
    required this.rotationRate,
    required this.stillHoldProgress,
    required this.motionHoldProgress,
    this.reason,
    this.caughtAt,
  });

  const DetectorSnapshot.idle()
      : state = DetectorState.idle,
        linearAcceleration = 0,
        rotationRate = 0,
        stillHoldProgress = 0,
        motionHoldProgress = 0,
        reason = null,
        caughtAt = null;

  final DetectorState state;

  /// Magnitude of acceleration with gravity removed, in m/s².
  final double linearAcceleration;

  /// Magnitude of the rotation rate, in rad/s.
  final double rotationRate;

  /// 0–1: how far through the stillness window we are while settling.
  final double stillHoldProgress;

  /// 0–1: how far through the sustained-motion window we are while armed.
  /// This is what stops a table bump from ending the game.
  final double motionHoldProgress;

  final CatchReason? reason;

  /// Elapsed time from the start of the round to the catch.
  final Duration? caughtAt;

  bool get isWatching =>
      state == DetectorState.settling || state == DetectorState.armed;

  @override
  String toString() => 'DetectorSnapshot(${state.name}, '
      'accel=${linearAcceleration.toStringAsFixed(2)}, '
      'gyro=${rotationRate.toStringAsFixed(2)}'
      '${reason != null ? ', ${reason!.name}' : ''})';
}
