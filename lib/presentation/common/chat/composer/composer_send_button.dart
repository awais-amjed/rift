import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';

/// The send button: solid accent once there's something to send, a muted
/// ghost arrow otherwise.
///
/// A rounded square the same size and radius as the other composer controls,
/// not a circle — it sits in a row of them, and the only thing that should
/// set it apart is that it's lit.
class ComposerSendButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const ComposerSendButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<ComposerSendButton> createState() => _ComposerSendButtonState();
}

class _ComposerSendButtonState extends State<ComposerSendButton> {
  /// Tracked rather than left to the ink, because the gradient is opaque: a
  /// hover highlight painted on the Material behind it would never be seen.
  /// The three buttons beside this one light up now, and a send button that
  /// stayed dead under the pointer would read as the broken one.
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final enabled = widget.enabled;
    final lit = enabled && _hovering;
    final radius = BorderRadius.circular(K.radiusRow);

    return Tooltip(
      message: 'Send',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: enabled ? widget.onPressed : null,
        onHover: (value) => setState(() => _hovering = value),
        borderRadius: radius,
        child: AnimatedContainer(
          duration: AppMotion.react,
          width: K.composerControlSize,
          height: K.composerControlSize,
          decoration: BoxDecoration(
            // Enabled, this is the accent, flat: the one filled control in
            // the composer is loud enough without a glow under it.
            color: enabled ? themeState.primary : null,
            borderRadius: radius,
          ),
          // A thin scrim over the fill, which is the only way to lift a
          // control whose own surface is opaque.
          foregroundDecoration: BoxDecoration(
            color: lit
                ? themeState.onPrimary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: radius,
          ),
          // Centred rather than filling the box, so the icon's bounds are the
          // glyph's — the composer's alignment is measured off them.
          child: Center(
            child: Icon(
              Icons.arrow_upward_rounded,
              size: 18,
              color: enabled ? themeState.onPrimary : themeState.textQuaternary,
            ),
          ),
        ),
      ),
    );
  }
}
