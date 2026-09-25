import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';

/// Small icon badge with tooltip used in member rows (admin, manager,
/// muted, deafened, ...).
class MemberBadge extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  const MemberBadge({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: K.tooltipDelay,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(K.radiusRow),
        ),
        child: Icon(icon, size: K.iconInline, color: color),
      ),
    );
  }
}
