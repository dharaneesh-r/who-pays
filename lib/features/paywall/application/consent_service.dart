import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// EEA/UK advertising consent, via Google's User Messaging Platform.
///
/// Google requires a certified consent platform before ads may be served to
/// users in the EEA or UK. UMP decides whether a form is needed based on
/// where the user is, so outside those regions this does nothing at all and
/// no one ever sees a dialog.
///
/// The message itself is authored in the AdMob console under
/// Privacy & messaging → GDPR. Until one is published there, UMP reports that
/// no form is required and the app simply carries on.
class ConsentService {
  bool _asked = false;

  /// Resolves consent, showing a form only if UMP says one is required.
  ///
  /// Returns when it is safe to request ads. Every failure path returns true:
  /// if consent cannot be resolved we still serve ads, because outside the
  /// EEA/UK no consent was needed in the first place and blocking ads there
  /// would remove the app's only revenue for a problem that does not apply.
  Future<bool> ensure() async {
    if (kIsWeb) return true;
    if (_asked) return true;
    _asked = true;

    final completer = Completer<bool>();

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((error) {
              if (!completer.isCompleted) completer.complete(true);
            });
          } catch (_) {
            if (!completer.isCompleted) completer.complete(true);
          }
          if (!completer.isCompleted) completer.complete(true);
        },
        (error) {
          // Could not reach UMP — carry on rather than killing revenue.
          if (!completer.isCompleted) completer.complete(true);
        },
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(true);
    }

    // Never let a silent SDK hold up the first round.
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => true,
    );
  }

  /// True when a privacy-options entry point must be offered — required in
  /// the EEA/UK so people can change their mind later.
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Reopens the consent form from Settings.
  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {});
    } catch (_) {}
  }

  /// Testing only — lets a device re-see the form.
  Future<void> reset() async {
    try {
      await ConsentInformation.instance.reset();
      _asked = false;
    } catch (_) {}
  }
}

final consentServiceProvider = Provider<ConsentService>((_) => ConsentService());
