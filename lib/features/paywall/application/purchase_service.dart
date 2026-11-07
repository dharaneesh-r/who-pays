import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/monetisation.dart';
import '../domain/entitlements.dart';

/// Buying, restoring and remembering what the player owns.
///
/// Entitlements are cached locally so the app opens unlocked with no network —
/// a restaurant with bad wifi must never show a paying customer a paywall.
/// The store remains the source of truth and corrects the cache on restore.
class PurchaseService extends AsyncNotifier<Entitlements> {
  static const _ownedKey = 'owned_products';

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  List<ProductDetails> products = const [];

  @override
  Future<Entitlements> build() async {
    ref.onDispose(() => _sub?.cancel());

    // Ads-only launch: nothing to buy, so never touch the billing client.
    if (!Monetisation.purchasesEnabled) return Entitlements.none;

    final cached = await _loadCached();

    // Listening and loading the catalogue are both best-effort: on a device
    // with no Play Store the app must still work, just without purchases.
    unawaited(_listen());
    unawaited(_loadProducts());

    return cached;
  }

  Future<Entitlements> _loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final owned = prefs.getStringList(_ownedKey) ?? const [];
    return Entitlements(owned: owned.toSet());
  }

  Future<void> _persist(Entitlements entitlements) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ownedKey, entitlements.owned.toList());
  }

  Future<void> _listen() async {
    try {
      if (!await _iap.isAvailable()) return;
      _sub = _iap.purchaseStream.listen(
        _onPurchases,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {/* no store on this device */}
  }

  Future<void> _loadProducts() async {
    try {
      if (!await _iap.isAvailable()) return;
      final response = await _iap.queryProductDetails(ProductIds.all);
      products = response.productDetails;
    } catch (_) {}
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    var entitlements = state.value ?? Entitlements.none;

    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          entitlements = entitlements.withPurchase(purchase.productID);
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          break;
        case PurchaseStatus.pending:
          continue;
      }

      // Required by both stores, and skipping it gets purchases refunded
      // automatically after three days.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }

    await _persist(entitlements);
    state = AsyncData(entitlements);
  }

  /// Everything here is non-consumable: bought once, owned forever.
  Future<void> buy(String productId) async {
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null) return;

    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Required on iOS, and the right thing on Android after a reinstall.
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  String priceOf(String productId) =>
      products.where((p) => p.id == productId).firstOrNull?.price ?? '';
}

final purchaseServiceProvider =
    AsyncNotifierProvider<PurchaseService, Entitlements>(PurchaseService.new);

/// Convenience for widgets: assume nothing is owned until proven otherwise.
final entitlementsProvider = Provider<Entitlements>((ref) {
  return ref.watch(purchaseServiceProvider).value ?? Entitlements.none;
});
