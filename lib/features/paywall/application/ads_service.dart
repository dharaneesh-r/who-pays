import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../data/remote/analytics_service.dart';
import 'consent_service.dart';
import 'purchase_service.dart';

/// Interstitial on the result screen only.
///
/// One ad, at the one moment the round is already over. No ad can ever appear
/// during a round: an interstitial mid-game would cover the timer the whole
/// table is watching, and an ad that makes someone grab their phone would
/// literally make them lose.
class AdsService {
  AdsService(this._ref);

  final Ref _ref;

  InterstitialAd? _ad;
  bool _loading = false;

  /// Google's public test units. Replace with the real ids from AdMob before
  /// release — shipping with these earns nothing, and serving live ads to
  /// yourself during testing gets the account banned.
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _realInterstitial = 'ca-app-pub-7599014130116297/9835901990';

  static const _unitId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL',
    defaultValue: kReleaseMode ? _realInterstitial : _testInterstitial,
  );

  bool get _adsAllowed => !_ref.read(entitlementsProvider).adsRemoved;

  Future<void> init() async {
    if (!_adsAllowed) return;
    try {
      // EEA/UK consent must be resolved before the first ad request. Outside
      // those regions this returns immediately without showing anything.
      await _ref.read(consentServiceProvider).ensure();
      await MobileAds.instance.initialize();
      await preload();
    } catch (_) {/* no Play Services on this device */}
  }

  Future<void> preload() async {
    if (!_adsAllowed || _ad != null || _loading) return;
    _loading = true;

    try {
      await InterstitialAd.load(
        adUnitId: _unitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _ad = ad;
            _loading = false;
          },
          onAdFailedToLoad: (_) {
            _ad = null;
            _loading = false;
          },
        ),
      );
    } catch (_) {
      _loading = false;
    }
  }

  /// Shows the ad if one is ready, and **completes only once it is gone**.
  ///
  /// `InterstitialAd.show()` resolves as soon as the ad appears, not when it
  /// is dismissed. Returning then meant the caller navigated or started the
  /// next round behind a full-screen ad — the player came back to the wrong
  /// screen, or to a round already running that they could not see.
  ///
  /// Returns immediately when there is no ad, so a player without one never
  /// waits.
  Future<void> maybeShowOnResult() async {
    if (!_adsAllowed) return;
    final ad = _ad;
    if (ad == null) {
      unawaited(preload());
      return;
    }

    _ad = null;
    final dismissed = Completer<void>();
    void finish(InterstitialAd shown) {
      shown.dispose();
      unawaited(preload());
      if (!dismissed.isCompleted) dismissed.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (shown, _) => finish(shown),
    );

    try {
      await ad.show();
      _ref.read(analyticsProvider).adShown();
    } catch (_) {
      finish(ad);
    }

    // A callback that never arrives must not strand the player on the result
    // screen forever.
    return dismissed.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}

final adsServiceProvider = Provider<AdsService>((ref) {
  final service = AdsService(ref);
  ref.onDispose(service.dispose);
  return service;
});
