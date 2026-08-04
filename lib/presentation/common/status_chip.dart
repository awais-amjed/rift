import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';

/// A small tinted pill stating a fact about the surface you're on —
/// "Encrypted", "Central".
///
/// Tinted from one colour rather than taking separate fill/border/text values,
/// so every chip in the app is the same recipe at a different hue.
class StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(K.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          Icon(icon, size: 11, color: color),
          Text(label, style: AppText.chip.copyWith(color: color)),
        ],
      ),
    );
  }
}
