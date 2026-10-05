import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The settings most people never need, behind a row that opens them.
///
/// Whether it is open is the caller's to keep: somebody who opened it once
/// finds it open the next time.
class AdvancedSettings extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  const AdvancedSettings({
    super.key,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: radius,
            hoverColor: theme.bgHover,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  AnimatedRotation(
                    turns: open ? 0 : -0.25,
                    duration: AppMotion.state,
                    curve: AppMotion.settle,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: K.iconButton,
                      color: theme.textTertiary,
                    ),
                  ),
                  Text(
                    'Advanced settings',
                    style: AppText.secondaryStrong.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.state,
          curve: AppMotion.settle,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(padding: const EdgeInsets.only(top: 8), child: child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
