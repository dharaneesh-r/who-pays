import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

  static const _unitId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL',
    defaultValue: _testInterstitial,
  );

  bool get _adsAllowed => !_ref.read(entitlementsProvider).adsRemoved;

  Future<void> init() async {
    if (!_adsAllowed) return;
    try {
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

  /// Shows the ad if one happens to be ready. Never blocks, never waits — the
  /// result screen appears instantly whether or not there is an ad.
  Future<void> maybeShowOnResult() async {
    if (!_adsAllowed) return;
    final ad = _ad;
    if (ad == null) {
      await preload();
      return;
    }

    _ad = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        preload();
      },
    );

    try {
      await ad.show();
    } catch (_) {
      ad.dispose();
    }
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
