import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../services/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  final VoidCallback onSubscribe;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  const PaywallScreen({
    super.key,
    required this.onSubscribe,
    required this.onRestore,
    required this.onClose,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final SubscriptionService _subscriptionService = SubscriptionService();

  bool _isLoading = true;
  bool _isPurchasing = false;
  String? _errorMessage;
  bool _isYearlySelected = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService().logPaywallViewed();
    _initStore();
  }

  Future<void> _initStore() async {
    try {
      await _subscriptionService.initialize();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _handlePurchase() async {
    if (_isPurchasing) return;
    setState(() {
      _isPurchasing = true;
      _errorMessage = null;
    });

    try {
      final productId = _isYearlySelected
          ? SubscriptionService.yearlyProductId
          : SubscriptionService.monthlyProductId;

      final success = await _subscriptionService.purchaseSubscription(productId);

      if (!success) {
        if (!mounted) return;
        setState(() {
          _isPurchasing = false;
          _errorMessage = 'Purchase not completed.';
        });
        return;
      }

      for (int i = 0; i < 6; i++) {
        final active = await _subscriptionService.hasActiveSubscription();
        if (active) {
          AnalyticsService().logSubscriptionPurchased(
            productId: productId,
            priceString: _isYearlySelected ? 'yearly' : 'monthly',
          );
          widget.onSubscribe();
          widget.onClose();
          return;
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() {
        _isPurchasing = false;
        _errorMessage = 'Processing... If it succeeded, tap "Restore Purchase".';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPurchasing = false;
        _errorMessage = 'Something went wrong.';
      });
    }
  }

  Future<void> _handleRestore() async {
    if (_isPurchasing) return;
    setState(() => _isPurchasing = true);

    try {
      await _subscriptionService.restorePurchases();
      final active = await _subscriptionService.hasActiveSubscription();
      if (active) {
        widget.onRestore();
        widget.onClose();
        return;
      }
      setState(() {
        _isPurchasing = false;
        _errorMessage = 'No purchases found.';
      });
    } catch (_) {
      setState(() {
        _isPurchasing = false;
        _errorMessage = 'Restore failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthly = _subscriptionService.monthlyProduct;
    final yearly = _subscriptionService.yearlyProduct;
    final monthlyPrice = monthly?.price ?? "\$4.99";
    final yearlyPrice = yearly?.price ?? "\$49.99";

    String savingsText = "Save 17%";
    if (monthly != null && yearly != null) {
      final monthlyRaw = monthly.rawPrice;
      final yearlyRaw = yearly.rawPrice;
      if (monthlyRaw > 0) {
        final yearlyEquivalent = monthlyRaw * 12;
        final savings = ((yearlyEquivalent - yearlyRaw) / yearlyEquivalent * 100).round();
        savingsText = "Save $savings%";
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white54, size: 20),
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // Logo
              Image.asset(
                'assets/logo.png',
                width: 80,
                height: 80,
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Go Pro',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Unlock the full power of VoiceBubble',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 40),

              // Two bullet points — clean and simple
              _bulletPoint('Best-in-class transcription'),
              const SizedBox(height: 16),
              _bulletPoint('Unlimited recordings and AI'),

              const SizedBox(height: 48),

              // Price toggle
              Row(
                children: [
                  // Monthly
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isYearlySelected = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: !_isYearlySelected
                              ? const Color(0xFF7C6AE8).withOpacity(0.15)
                              : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !_isYearlySelected
                                ? const Color(0xFF7C6AE8)
                                : Colors.white.withOpacity(0.08),
                            width: !_isYearlySelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Monthly',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              monthlyPrice,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Yearly
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isYearlySelected = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: _isYearlySelected
                              ? const Color(0xFF7C6AE8).withOpacity(0.15)
                              : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _isYearlySelected
                                ? const Color(0xFF7C6AE8)
                                : Colors.white.withOpacity(0.08),
                            width: _isYearlySelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              savingsText,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7C6AE8),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              yearlyPrice,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '/year',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Error
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Subscribe button
              GestureDetector(
                onTap: _isLoading || _isPurchasing ? null : _handlePurchase,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C6AE8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      _isPurchasing ? 'Processing...' : 'Subscribe',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Restore
              GestureDetector(
                onTap: _isLoading || _isPurchasing ? null : _handleRestore,
                child: Text(
                  'Restore Purchase',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // Legal
              Text(
                'Cancel anytime. Subscription auto-renews.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.25),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF7C6AE8).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.check, color: Color(0xFF7C6AE8), size: 16),
        ),
        const SizedBox(width: 14),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
