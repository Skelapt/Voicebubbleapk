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
    // Use the *regular* recurring price, not the introductory/free-trial
    // phase. Otherwise a yearly plan with a 7-day free trial shows as $0.00.
    final monthlyInfo = monthly != null ? _subscriptionService.regularPriceOf(monthly) : null;
    final yearlyInfo = yearly != null ? _subscriptionService.regularPriceOf(yearly) : null;

    // Big price on each card = the actual formatted price from Play Store.
    final monthlyPrice = monthlyInfo?.formatted ?? "\$4.99";
    final yearlyPrice = yearlyInfo?.formatted ?? "\$49.99";

    // Subtitle on each card — must clearly state the actual BILLING
    // cadence (Google Play subscriptions policy: "how often the users
    // will be charged"). Previously the yearly card showed only the
    // per-month *equivalent* (e.g. "₹533.33/month"), which is
    // misleading because the user is charged once per year. Both cards
    // now lead with "Billed monthly" / "Billed yearly" so the cadence
    // is unambiguous; the yearly card also shows the per-month
    // equivalent as a small extra so users can still compare.
    final monthlySubtitle = 'Billed monthly';
    String yearlySubtitle = 'Billed yearly';
    if (yearlyInfo != null && yearlyInfo.raw > 0) {
      final perMonth = yearlyInfo.raw / 12;
      yearlySubtitle =
          'Billed yearly • ~${yearlyInfo.currencySymbol}${perMonth.toStringAsFixed(2)}/mo';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
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

                const SizedBox(height: 12),

                // Logo
                Image.asset('assets/logo.png', width: 64, height: 64),
                const SizedBox(height: 14),

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

                const SizedBox(height: 24),

                // 3 feature bullets — bigger text
                _feature(Icons.mic_none_rounded, 'Unlimited voice-to-text transcriptions'),
                _feature(Icons.auto_awesome_rounded, 'Unlimited AI rewrites'),
                _feature(Icons.upload_file_rounded, 'Upload audio files for transcription'),

                const SizedBox(height: 22),

                // Two price cards — IDENTICAL size (height 100). No outer
                // padding: the floating "7-DAY TRIAL" badge is a Positioned
                // overlay at top: -10 inside a Stack(clipBehavior: Clip.none),
                // so it overhangs into the SizedBox(height: 28) above without
                // displacing anything else on the page.
                Row(
                  children: [
                    Expanded(
                      child: _priceCard(
                        selected: !_isYearlySelected,
                        onTap: () => setState(() => _isYearlySelected = false),
                        label: 'Monthly',
                        price: monthlyPrice,
                        subtitle: monthlySubtitle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _priceCard(
                        selected: _isYearlySelected,
                        onTap: () => setState(() => _isYearlySelected = true),
                        label: 'Yearly',
                        price: yearlyPrice,
                        subtitle: yearlySubtitle,
                        badge: '7-DAY TRIAL',
                      ),
                    ),
                  ],
                ),

                // Belt-and-braces trial-end disclosure, sitting BETWEEN
                // the price cards and the CTA, mirroring exactly what
                // the user is about to commit to. Google Play rejects
                // paywalls where the trial-end price is anywhere except
                // adjacent to the trial badge — not buried in fine
                // print 200px below.
                if (_isYearlySelected) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C6AE8).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7C6AE8).withOpacity(0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF7C6AE8)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Free for 7 days, then $yearlyPrice billed once per year. '
                            'Auto-renews yearly until you cancel.',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Error
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12), textAlign: TextAlign.center),
                  ),

                // CTA Button — green. The label itself spells out the
                // full charge and cadence so a user can never tap
                // "Subscribe" without seeing exactly what they are
                // committing to. This is the single most common reason
                // Google Play rejects a subscription paywall.
                GestureDetector(
                  onTap: _isLoading || _isPurchasing ? null : _handlePurchase,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF34C759).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Center(
                      child: _isPurchasing
                          ? const Text(
                              'Processing…',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _isYearlySelected
                                      ? 'Start 7-day free trial'
                                      : 'Subscribe',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.1),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isYearlySelected
                                      ? 'then $yearlyPrice / year • auto-renews'
                                      : '$monthlyPrice / month • auto-renews',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      height: 1.2),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Explicit subscription terms — Google Play's
                // Subscriptions policy requires every paid offer to
                // clearly state, on the same screen as the purchase
                // button: (1) the cost, (2) the billing frequency,
                // (3) what the subscription includes, (4) the length
                // and conditions of any free trial / introductory
                // offer, (5) that the subscription auto-renews until
                // cancelled, and (6) how to cancel. All six items are
                // restated in plain language directly under the CTA so
                // they are part of the offer, not buried fine print.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _isYearlySelected
                        ? 'Your 7-day free trial begins immediately. After the '
                            'trial ends, your Google Play account will be charged '
                            '$yearlyPrice for one year of VoiceBubble Pro. The '
                            'subscription automatically renews at $yearlyPrice '
                            'every year unless you cancel at least 24 hours '
                            'before the renewal date. Pro unlocks unlimited '
                            'transcriptions, unlimited AI rewrites and audio '
                            'file uploads. A subscription is not required to '
                            'use VoiceBubble — Pro features are optional. '
                            'You can cancel anytime in Google Play → '
                            'Subscriptions; cancellations stop future renewals '
                            'and refunds follow Google Play\'s standard policy.'
                        : 'Your Google Play account will be charged $monthlyPrice '
                            'for one month of VoiceBubble Pro as soon as you '
                            'confirm. The subscription automatically renews at '
                            '$monthlyPrice every month unless you cancel at '
                            'least 24 hours before the renewal date. Pro unlocks '
                            'unlimited transcriptions, unlimited AI rewrites and '
                            'audio file uploads. A subscription is not required '
                            'to use VoiceBubble — Pro features are optional. '
                            'You can cancel anytime in Google Play → '
                            'Subscriptions; cancellations stop future renewals '
                            'and refunds follow Google Play\'s standard policy.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: Colors.white.withOpacity(0.78),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 14),

                // Restore
                GestureDetector(
                  onTap: _isLoading || _isPurchasing ? null : _handleRestore,
                  child: Text('Restore Purchase', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.45))),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Price card — EXACT old size (height 100, vertical padding 14). Both
  /// monthly and yearly use the same structure so users can compare at a
  /// glance. Passing a non-null [badge] renders a pill floating over the
  /// top edge of the card; the card itself is not resized or padded.
  Widget _priceCard({
    required bool selected,
    required VoidCallback onTap,
    required String label,
    required String price,
    required String subtitle,
    String? badge,
  }) {
    // Always return a SizedBox(height: 100) with a Stack inside. This makes
    // monthly and yearly cards IDENTICAL in layout structure so they can
    // never differ in size. The badge (if any) is a Positioned overlay that
    // overhangs the top edge without changing the card's footprint.
    return SizedBox(
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // The card fills the SizedBox entirely
          Positioned.fill(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF7C6AE8).withOpacity(0.12)
                      : Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF7C6AE8)
                        : Colors.white.withOpacity(0.08),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Floating "7-DAY TRIAL" badge — pure overlay, doesn't affect size
          if (badge != null)
            Positioned(
              top: -10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF34C759).withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
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
