import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';
import 'stream_glass.dart';

/// One glass button in the corner of a watched stream.
class StreamCornerButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const StreamCornerButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: StreamGlass(
        child: StreamCornerIcon(icon: icon, onTap: onTap),
      ),
    );
  }
}

/// The pressable icon inside a [StreamGlass], for a control that puts more
/// than a button on the glass.
class StreamCornerIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  /// Hands over how the press was made — a touch, or a mouse — for a
  /// control that answers the two differently.
  final GestureTapDownCallback? onTapDown;

  const StreamCornerIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.onTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(K.radiusRow),
      hoverColor: theme.bgHover,
      onTapDown: onTapDown,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: K.iconButton, color: theme.textSecondary),
      ),
    );
  }
}
