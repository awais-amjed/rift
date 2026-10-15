import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/custom_colors.dart';
import '../theme/theme_context.dart';

/// The trash can at the end of a list row: a sound, a region, a webhook.
///
/// An icon, not a button with a word on it. `QuietDangerButton` is sized to
/// be one option among several in a stacked list; in a dense row it is a slab
/// of red beside two bare glyphs, and it reads as the point of the row rather
/// than as the thing you reach for once. The weight this action needs is
/// carried by the confirmation it opens, not by the control that opens it.
///
/// Red on approach rather than at rest: enough to say what it does before it
/// is pressed, quiet enough to stay in a list. It used to be red at rest in
/// one list and grey in the two beside it.
class RowDeleteButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;

  /// The trash can, unless the row's removal is not a deletion: a bot kicked
  /// from the Bots page leaves the server, it is not destroyed.
  final IconData icon;

  const RowDeleteButton({
    super.key,
    required this.tooltip,
    this.onPressed,
    this.icon = Icons.delete_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final danger = theme.statusInk(CustomColors.error);
    return IconButton(
      tooltip: tooltip,
      mouseCursor: WidgetStateMouseCursor.clickable,
      icon: Icon(icon, size: K.iconButton),
      hoverColor: CustomColors.error.withValues(alpha: 0.10),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? danger
              : theme.textTertiary,
        ),
      ),
      onPressed: onPressed,
    );
  }
}
