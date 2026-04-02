import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
// Firestore removed - subscription is now pure local
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  // Product IDs - CHANGE THESE to match your App Store Connect & Google Play Console
  static const String monthlyProductId = 'voicebubble_pro_monthly';
  static const String yearlyProductId = 'voicebubble_pro_yearly';
  
  final Set<String> _productIds = {monthlyProductId, yearlyProductId};
  
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _purchasePending = false;
  String? _queryProductError;

  // Getters
  bool get isAvailable => _isAvailable;
  bool get purchasePending => _purchasePending;
  List<ProductDetails> get products => _products;
  ProductDetails? get monthlyProduct => _products.where((p) => p.id == monthlyProductId).firstOrNull;
  ProductDetails? get yearlyProduct => _products.where((p) => p.id == yearlyProductId).firstOrNull;

  /// Initialize the IAP system
  Future<void> initialize() async {
    debugPrint('🛒 Initializing In-App Purchase system...');
    
    // Check if IAP is available
    _isAvailable = await _iap.isAvailable();
    
    if (!_isAvailable) {
      debugPrint('❌ IAP not available on this device');
      return;
    }
    
    debugPrint('✅ IAP is available');
    
    // Set up platform-specific configurations
    if (Platform.isAndroid) {
      // Note: enablePendingPurchases() is deprecated and no longer needed
      // The newer versions of in_app_purchase_android handle this automatically
      debugPrint('✅ Android IAP configured (pending purchases handled automatically)');
    }
    
    // Listen for purchase updates
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => debugPrint('🔚 Purchase stream done'),
      onError: (error) => debugPrint('❌ Purchase stream error: $error'),
    );
    
    // Load products
    await loadProducts();
  }

  /// Load available products from stores
  Future<void> loadProducts() async {
    debugPrint('📦 Loading products: $_productIds');
    
    final ProductDetailsResponse response = await _iap.queryProductDetails(_productIds);
    
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('⚠️ Products not found: ${response.notFoundIDs}');
      _queryProductError = 'Products not found: ${response.notFoundIDs}';
    }
    
    if (response.error != null) {
      debugPrint('❌ Error loading products: ${response.error}');
      _queryProductError = response.error!.message;
      return;
    }
    
    _products = response.productDetails;
    debugPrint('✅ Loaded ${_products.length} products:');
    for (var product in _products) {
      debugPrint('  - ${product.id}: ${product.title} (${product.price})');
    }
  }

  /// Purchase a subscription
  Future<bool> purchaseSubscription(String productId) async {
    debugPrint('💳 Purchasing subscription: $productId');
    
    final ProductDetails? productDetails = _products.where((p) => p.id == productId).firstOrNull;
    
    if (productDetails == null) {
      debugPrint('❌ Product not found: $productId');
      return false;
    }
    
    _purchasePending = true;
    
    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: productDetails,
    );
    
    try {
      final bool success = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      debugPrint('Purchase initiated: $success');
      return success;
    } catch (e) {
      debugPrint('❌ Error initiating purchase: $e');
      _purchasePending = false;
      return false;
    }
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    debugPrint('🔄 Restoring purchases...');
    
    try {
      await _iap.restorePurchases();
      debugPrint('✅ Restore purchases completed');
    } catch (e) {
      debugPrint('❌ Error restoring purchases: $e');
      rethrow;
    }
  }

  /// Handle purchase updates from the store
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    debugPrint('📬 Purchase update received: ${purchaseDetailsList.length} items');
    
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      debugPrint('Purchase status: ${purchaseDetails.status} for ${purchaseDetails.productID}');
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        debugPrint('⏳ Purchase pending...');
        _purchasePending = true;
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint('❌ Purchase error: ${purchaseDetails.error}');
          _purchasePending = false;
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          debugPrint('✅ Purchase successful/restored!');
          
          // Verify and deliver purchase
          final bool valid = await _verifyPurchase(purchaseDetails);
          
          if (valid) {
            await _deliverProduct(purchaseDetails);
          } else {
            debugPrint('❌ Purchase verification failed');
          }
          
          _purchasePending = false;
        }
        
        // Complete the purchase
        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
          debugPrint('✅ Purchase marked as complete');
        }
      }
    }
  }

  /// Verify purchase with backend (you should implement server-side validation)
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    debugPrint('🔐 Verifying purchase: ${purchaseDetails.productID}');
    
    // TODO: Send receipt to your backend for validation
    // For now, we'll do basic validation
    
    if (Platform.isIOS) {
      // iOS receipt validation
      final String receiptData = purchaseDetails.verificationData.serverVerificationData;
      debugPrint('📱 iOS receipt data available: ${receiptData.length} characters');
      // TODO: Send to backend for validation with Apple
    } else if (Platform.isAndroid) {
      // Android receipt validation
      final GooglePlayPurchaseDetails googleDetails = purchaseDetails as GooglePlayPurchaseDetails;
      debugPrint('🤖 Android purchase token: ${googleDetails.billingClientPurchase.purchaseToken}');
      // TODO: Send to backend for validation with Google
    }
    
    // For now, return true (but you MUST implement backend validation for production!)
    return true;
  }

  // Local subscription storage keys
  static const String _keyLocalIsPro = 'local_is_pro';
  static const String _keyLocalExpiryDate = 'local_expiry_date';
  static const String _keyLocalSubType = 'local_sub_type';
  static const String _keyLocalProductId = 'local_product_id';

  /// Deliver the product to the user (save locally - no Firestore)
  Future<void> _deliverProduct(PurchaseDetails purchaseDetails) async {
    debugPrint('📦 Delivering product: ${purchaseDetails.productID}');

    // Determine subscription type
    String subscriptionType = 'monthly';
    DateTime expiryDate;

    if (purchaseDetails.productID == yearlyProductId) {
      subscriptionType = 'yearly';
      expiryDate = DateTime.now().add(const Duration(days: 365));
    } else {
      expiryDate = DateTime.now().add(const Duration(days: 30));
    }

    // Save locally - works offline, instant, no Firestore
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLocalIsPro, true);
      await prefs.setString(_keyLocalExpiryDate, expiryDate.toIso8601String());
      await prefs.setString(_keyLocalSubType, subscriptionType);
      await prefs.setString(_keyLocalProductId, purchaseDetails.productID);

      debugPrint('✅ Subscription saved locally: $subscriptionType, expires: $expiryDate');

      // Cancel retention notifications — they're a paying customer now
      try {
        final ns = NotificationService();
        for (final id in [900001, 900002, 900003, 900004, 900005, 900006, 900007]) {
          await ns.cancelReminder(id);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ Error saving subscription locally: $e');
    }
  }

  /// Alias for feature gates: Pro = has active subscription
  Future<bool> isPro() async {
    return await hasActiveSubscription();
  }

  /// Check if user has active subscription (pure local - no Firestore)
  Future<bool> hasActiveSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isPro = prefs.getBool(_keyLocalIsPro) ?? false;

      if (!isPro) {
        debugPrint('🔍 Subscription: not pro (local)');
        return false;
      }

      final expiryStr = prefs.getString(_keyLocalExpiryDate);
      if (expiryStr == null) {
        debugPrint('🔍 Subscription: no expiry date found (local)');
        return false;
      }

      final expiryDate = DateTime.parse(expiryStr);
      final isActive = DateTime.now().isBefore(expiryDate);

      debugPrint('🔍 Subscription active: $isActive (expires: $expiryDate) [local]');
      return isActive;
    } catch (e) {
      debugPrint('❌ Error checking local subscription: $e');
      return false;
    }
  }

  /// Review prompts (stored locally)
  static const String _keyAskedReviewAfterUpgrade = 'asked_review_after_upgrade';
  static const String _keyHasLeftReview = 'has_left_review';

  Future<bool> hasAskedForReviewAfterUpgrade() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAskedReviewAfterUpgrade) ?? false;
  }

  Future<void> markAskedForReviewAfterUpgrade() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAskedReviewAfterUpgrade, true);
  }

  Future<bool> hasLeftReview() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasLeftReview) ?? false;
  }

  Future<void> markLeftReview() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasLeftReview, true);
  }

  /// Dispose subscriptions
  void dispose() {
    _subscription.cancel();
    debugPrint('🛑 SubscriptionService disposed');
  }
}

