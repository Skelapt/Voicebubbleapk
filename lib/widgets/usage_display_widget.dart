import 'package:flutter/material.dart';
import '../services/usage_service.dart';
import '../services/subscription_service.dart';
import '../screens/paywall/paywall_screen.dart';

/// Widget to display STT/AI usage in settings
class UsageDisplayWidget extends StatefulWidget {
  const UsageDisplayWidget({super.key});

  @override
  State<UsageDisplayWidget> createState() => _UsageDisplayWidgetState();
}

class _UsageDisplayWidgetState extends State<UsageDisplayWidget> {
  final UsageService _usageService = UsageService();
  final SubscriptionService _subService = SubscriptionService();

  bool _isPro = false;
  int _secondsUsed = 0;
  int _totalLimit = 0;
  bool _hasReviewBonus = false;
  bool _hasOnboardingBonus = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final isPro = await _subService.isPro();
    final secondsUsed = await _usageService.getSecondsUsed();
    final totalLimit = await _usageService.getTotalLimit(isPro: isPro);
    final hasReviewBonus = await _usageService.hasClaimedReviewBonus();
    final hasOnboardingBonus = await _usageService.hasClaimedOnboardingBonus();

    setState(() {
      _isPro = isPro;
      _secondsUsed = secondsUsed;
      _totalLimit = totalLimit;
      _hasReviewBonus = hasReviewBonus;
      _hasOnboardingBonus = hasOnboardingBonus;
      _isLoading = false;
    });
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const surfaceColor = Color(0xFF1A1A1A);
    const textColor = Colors.white;
    const secondaryTextColor = Color(0xFF94A3B8);
    const primaryColor = Color(0xFF3B82F6);
    const accentColor = Color(0xFFF59E0B);

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    final remaining = (_totalLimit - _secondsUsed).clamp(0, _totalLimit);
    final percentage = _isPro || _totalLimit == 0
        ? 0.0
        : (_secondsUsed / _totalLimit); // Pro / pre-bonus = empty bar
    final isLow = _isPro ? false : percentage > 0.8;
    final isExhausted = _isPro || !_hasOnboardingBonus ? false : remaining <= 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: _isPro
            ? Border.all(color: accentColor.withOpacity(0.5), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.timer,
                  color: primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'STT & AI Time',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_isPro) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Resets monthly',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isPro)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PaywallScreen(
                          onSubscribe: () => Navigator.pop(context, true),
                          onRestore: () => Navigator.pop(context, true),
                          onClose: () => Navigator.pop(context),
                        ),
                      ),
                    ).then((_) => _loadData());
                  },
                  child: const Text(
                    'Upgrade',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percentage.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isExhausted
                    ? const Color(0xFFEF4444)
                    : isLow
                        ? accentColor
                        : primaryColor,
              ),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatTime(_secondsUsed)} used',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 13,
                ),
              ),
              Text(
                _isPro ? 'Unlimited' : '${_formatTime(remaining)} remaining',
                style: TextStyle(
                  color: _isPro
                      ? const Color(0xFF7C6AE8)
                      : isExhausted
                          ? const Color(0xFFEF4444)
                          : isLow
                              ? accentColor
                              : const Color(0xFF10B981),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (!_isPro && _hasReviewBonus) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.card_giftcard,
                    color: Color(0xFF10B981),
                    size: 14,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '+1 min review bonus active',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: secondaryTextColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isPro
                        ? 'Pro: Unlimited recordings & AI'
                        : _hasOnboardingBonus
                            ? 'Pro: ${(_totalLimit / 60).floor()} minutes unlocked this month'
                            : 'Record your first message to unlock 10 min of Pro',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact version for inline display
class UsageDisplayCompact extends StatefulWidget {
  final VoidCallback? onTap;

  const UsageDisplayCompact({super.key, this.onTap});

  @override
  State<UsageDisplayCompact> createState() => _UsageDisplayCompactState();
}

class _UsageDisplayCompactState extends State<UsageDisplayCompact> {
  final UsageService _usageService = UsageService();
  final SubscriptionService _subService = SubscriptionService();

  String _displayText = 'Loading...';
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final isPro = await _subService.isPro();
    final remaining = await _usageService.getRemainingSeconds(isPro: isPro);
    final mins = remaining ~/ 60;
    final secs = remaining % 60;

    setState(() {
      _isPro = isPro;
      _displayText = '$mins:${secs.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF3B82F6);
    const accentColor = Color(0xFFF59E0B);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (_isPro ? accentColor : primaryColor).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (_isPro ? accentColor : primaryColor).withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer,
              color: _isPro ? accentColor : primaryColor,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              _displayText,
              style: TextStyle(
                color: _isPro ? accentColor : primaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_isPro) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.workspace_premium,
                color: accentColor,
                size: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
