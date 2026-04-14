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
  bool _isYearlySelected = true; // Pre-select yearly

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

    // Calculate weekly price and savings
    String weeklyPrice = "\$0.96";
    String savingsText = "SAVE 60%";
    if (yearly != null) {
      final weekly = yearly.rawPrice / 52;
      weeklyPrice = "\$${weekly.toStringAsFixed(2)}";
    }
    if (monthly != null && yearly != null) {
      final monthlyRaw = monthly.rawPrice;
      final yearlyRaw = yearly.rawPrice;
      if (monthlyRaw > 0) {
        final yearlyEquivalent = monthlyRaw * 12;
        final savings = ((yearlyEquivalent - yearlyRaw) / yearlyEquivalent * 100).round();
        savingsText = "SAVE $savings%";
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
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white38, size: 18),
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // Logo
              Image.asset('assets/logo.png', width: 68, height: 68),
              const SizedBox(height: 16),

              // Title
              const Text(
                'Go Pro',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
              ),
              const SizedBox(height: 6),
              Text(
                'Unlock the full power of VoiceBubble',
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.45)),
              ),

              const SizedBox(height: 12),

              // Social proof — centered stars
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ...List.generate(5, (i) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 1),
                    child: Icon(Icons.star_rounded, size: 20, color: Color(0xFFFFD700)),
                  )),
                  const SizedBox(width: 8),
                  Text('4.8', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.9))),
                ],
              ),

              const SizedBox(height: 28),

              // 3 feature bullets — bigger text
              _feature(Icons.mic_none_rounded, 'Unlimited voice-to-text transcriptions'),
              _feature(Icons.auto_awesome_rounded, 'Unlimited AI rewrites'),
              _feature(Icons.upload_file_rounded, 'Upload audio files for transcription'),

              const SizedBox(height: 28),

              // Two price cards — IDENTICAL SIZE
              Row(
                children: [
                  // Monthly
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isYearlySelected = false),
                      child: Container(
                        height: 100,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: !_isYearlySelected
                              ? const Color(0xFF7C6AE8).withOpacity(0.12)
                              : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !_isYearlySelected
                                ? const Color(0xFF7C6AE8)
                                : Colors.white.withOpacity(0.08),
                            width: !_isYearlySelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Monthly', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            Text(monthlyPrice, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('/month', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Yearly — with savings badge
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isYearlySelected = true),
                      child: Container(
                        height: 100,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _isYearlySelected
                              ? const Color(0xFF7C6AE8).withOpacity(0.12)
                              : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _isYearlySelected
                                ? const Color(0xFF7C6AE8)
                                : Colors.white.withOpacity(0.08),
                            width: _isYearlySelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(savingsText, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
                            ),
                            const SizedBox(height: 4),
                            Text(weeklyPrice, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('/week ($yearlyPrice/yr)', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.35))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Error
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
                ),

              // CTA Button — green
              GestureDetector(
                onTap: _isLoading || _isPurchasing ? null : _handlePurchase,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF34C759).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _isPurchasing
                          ? 'Processing...'
                          : _isYearlySelected
                              ? 'Start 7-Day Free Trial'
                              : 'Subscribe',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isYearlySelected ? 'Cancel anytime \u2022 You won\'t be charged today' : 'Cancel anytime \u2022 No commitment',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3)),
              ),

              const SizedBox(height: 16),

              // Restore + legal
              GestureDetector(
                onTap: _isLoading || _isPurchasing ? null : _handleRestore,
                child: Text('Restore Purchase', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.35))),
              ),
              const SizedBox(height: 6),
              Text(
                'Subscription auto-renews. Cancel anytime in settings.',
                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.2)),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF7C6AE8).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF7C6AE8), size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white, height: 1.2)),
          ),
        ],
      ),
    );
  }
}
