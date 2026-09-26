import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// One of a pinned row's two small buttons — Jump, Unpin.
///
/// Words rather than icons: an × on a pinned message read as "close" or
/// "delete", and there is no pin-with-a-slash that everybody recognises.
class PinnedTileAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const PinnedTileAction({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: themeState.bgElevated,
        borderRadius: radius,
        border: Border.all(color: themeState.borderElevated),
      ),
      // Inside the fill, so the hover lands on top of it.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              label,
              style: AppText.chip.copyWith(color: themeState.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
