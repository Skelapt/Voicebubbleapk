import 'package:flutter/material.dart';
import '../services/refinement_service.dart';

class RefinementButtons extends StatelessWidget {
  final String currentText;
  final Function(String refinedText) onRefinementComplete;
  final RefinementType? activeRefinement;

  const RefinementButtons({
    super.key,
    required this.currentText,
    required this.onRefinementComplete,
    this.activeRefinement,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Refine with AI',
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildRefinementButton(
              context,
              icon: Icons.compress,
              label: 'Shorten',
              refinementType: RefinementType.shorten,
              surfaceColor: surfaceColor,
              textColor: textColor,
            ),
            _buildRefinementButton(
              context,
              icon: Icons.expand,
              label: 'Expand',
              refinementType: RefinementType.expand,
              surfaceColor: surfaceColor,
              textColor: textColor,
            ),
            _buildRefinementButton(
              context,
              icon: Icons.sentiment_satisfied,
              label: 'Casual',
              refinementType: RefinementType.casual,
              surfaceColor: surfaceColor,
              textColor: textColor,
            ),
            _buildRefinementButton(
              context,
              icon: Icons.business_center,
              label: 'Professional',
              refinementType: RefinementType.professional,
              surfaceColor: surfaceColor,
              textColor: textColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRefinementButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required RefinementType refinementType,
    required Color surfaceColor,
    required Color textColor,
  }) {
    final isActive = activeRefinement == refinementType;
    final primaryColor = const Color(0xFF7C6AE8);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isActive
            ? null
            : () async {
                try {
                  final service = RefinementService();
                  String refined;

                  switch (refinementType) {
                    case RefinementType.shorten:
                      refined = await service.shorten(currentText);
                      break;
                    case RefinementType.expand:
                      refined = await service.expand(currentText);
                      break;
                    case RefinementType.casual:
                      refined = await service.makeCasual(currentText);
                      break;
                    case RefinementType.professional:
                      refined = await service.makeProfessional(currentText);
                      break;
                    case RefinementType.fixGrammar:
                      refined = await service.fixGrammar(currentText);
                      break;
                    case RefinementType.translate:
                      refined = await service.translate(currentText, 'en');
                      break;
                  }

                  onRefinementComplete(refined);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to refine: ${e.toString()}'),
                        backgroundColor: const Color(0xFFEF4444),
                      ),
                    );
                  }
                }
              },
        borderRadius: BorderRadius.circular(12),
        splashColor: primaryColor.withOpacity(0.2),
        highlightColor: primaryColor.withOpacity(0.1),
        child: Ink(
          decoration: BoxDecoration(
            color: isActive ? primaryColor.withOpacity(0.2) : surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  )
                else
                  Icon(icon, size: 16, color: textColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? primaryColor : textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
