import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';

/// A uniform, square tap target for the composer's actions (attach, emoji,
/// mic, discard, stop). Fixed size so every control lines up on the same
/// centre line regardless of which icon it carries.
class ComposerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final ThemeState themeState;
  final VoidCallback? onPressed;

  /// Tints the icon with the accent — used while a mode is engaged (the emoji
  /// panel is open, a recording is running).
  final bool active;

  const ComposerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.themeState,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = active
        ? themeState.primary
        : (enabled ? themeState.textTertiary : themeState.textQuaternary);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        // Rounded squares, matching the send button beside them — a row of
        // circles around one square reads as a mistake.
        borderRadius: BorderRadius.circular(K.composerControlRadius),
        hoverColor: themeState.bgHover,
        child: SizedBox(
          width: K.composerControlSize,
          height: K.composerControlSize,
          child: Center(
            child: Icon(icon, size: K.composerIconSize, color: color),
          ),
        ),
      ),
    );
  }
}
