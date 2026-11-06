/// Every number that decides whether a player gets caught lives here.
///
/// These are the most important values in the app: too sensitive and a passing
/// truck ends the game, too loose and people cheat. They move to Firebase
/// Remote Config later so they can be tuned without a release.
abstract final class DetectionConfig {
  /// Accelerometer / gyroscope sample rate.
  static const Duration samplingInterval = Duration(milliseconds: 20); // 50 Hz

  /// Low-pass filter weight for the gravity estimate (0–1, higher = smoother).
  static const double gravitySmoothing = 0.85;

  /// While settling: how still the phone must be to count as "placed down",
  /// in m/s² of deviation from gravity.
  static const double stillnessTolerance = 0.35;

  /// While settling: how long it must stay still before the game arms.
  static const Duration stillnessWindow = Duration(milliseconds: 1200);

  /// Armed: linear acceleration (m/s², gravity removed) that counts as movement.
  static const double pickUpAccelThreshold = 1.6;

  /// Armed: rotation rate (rad/s) that counts as movement.
  static const double pickUpGyroThreshold = 1.1;

  /// Armed: how long movement must be sustained to be a real pick-up rather
  /// than a table bump. This single value prevents most false positives.
  static const Duration sustainedMotionWindow = Duration(milliseconds: 180);

  /// Grace period after arming, so putting the phone down doesn't trip it.
  static const Duration armingGrace = Duration(seconds: 3);

  /// Each player's one free emergency pass per game.
  static const Duration emergencyPassDuration = Duration(seconds: 30);
}
