import 'package:flutter/material.dart';
import '../models/tag.dart';

class TagChip extends StatelessWidget {
  final Tag tag;
  final bool isSelected;
  final bool showRemove;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String size; // 'small' or 'large'

  const TagChip({
    super.key,
    required this.tag,
    this.isSelected = false,
    this.showRemove = false,
    this.onTap,
    this.onRemove,
    this.size = 'small',
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.color);
    final isLarge = size == 'large';
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isLarge ? 12 : 10,
          vertical: isLarge ? 7 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(isLarge ? 18 : 14),
          border: Border.all(
            color: color.withOpacity(isSelected ? 0.8 : 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color dot
            Container(
              width: isLarge ? 10 : 8,
              height: isLarge ? 10 : 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.white : color,
              ),
            ),
            SizedBox(width: isLarge ? 8 : 6),
            // Tag name
            Text(
              tag.name,
              style: TextStyle(
                fontSize: isLarge ? 13 : 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Remove button
            if (showRemove) ...[
              SizedBox(width: isLarge ? 6 : 4),
              GestureDetector(
                onTap: onRemove,
                child: Icon(
                  Icons.close,
                  size: isLarge ? 16 : 12,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
