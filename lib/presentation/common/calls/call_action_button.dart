import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../theme/custom_colors.dart';

/// The round button a call is answered or ended with. Round, filled and
/// larger than any other control, because these two are pressed in a hurry
/// and the wrong one cannot be taken back.
class CallActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool accept;
  final VoidCallback? onTap;

  /// Answer: green, the phone lifted.
  const CallActionButton.accept({
    super.key,
    required this.onTap,
    this.tooltip = 'Answer',
    this.icon = Icons.call_rounded,
  }) : accept = true;

  /// Decline or hang up: red, the phone put down.
  const CallActionButton.end({
    super.key,
    required this.onTap,
    this.tooltip = 'Hang up',
    this.icon = Icons.call_end_rounded,
  }) : accept = false;

  @override
  Widget build(BuildContext context) {
    final fill = accept ? CustomColors.success : CustomColors.error;
    final ink = accept ? CustomColors.onSuccess : CustomColors.onError;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: K.callActionSize,
        child: Material(
          color: onTap == null ? fill.withValues(alpha: 0.5) : fill,
          shape: const CircleBorder(),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: K.iconCallAction, color: ink),
          ),
        ),
      ),
    );
  }
}
