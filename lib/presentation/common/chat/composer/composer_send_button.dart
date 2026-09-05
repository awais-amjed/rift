import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_shadows.dart';

/// The send button: the action gradient once there's something to send, a
/// muted ghost arrow otherwise.
///
/// A rounded square the same size and radius as the other composer controls,
/// not a circle — it sits in a row of them, and the only thing that should
/// set it apart is that it's lit.
class ComposerSendButton extends StatefulWidget {
  final ThemeState themeState;
  final bool enabled;
  final VoidCallback onPressed;

  const ComposerSendButton({
    super.key,
    required this.themeState,
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
    final themeState = widget.themeState;
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
          duration: const Duration(milliseconds: 120),
          width: K.composerControlSize,
          height: K.composerControlSize,
          decoration: BoxDecoration(
            // Enabled, this is the app's one action gradient, lit from below —
            // the loudest control on screen, which is right for the only
            // irreversible thing in the composer.
            gradient: enabled ? themeState.actionGradient : null,
            borderRadius: radius,
            // Hovering makes it louder rather than tinting it — brightening a
            // gradient muddies it, and the glow is what this control already
            // says "press me" with.
            boxShadow: enabled
                ? AppShadows.accentGlow(
                    themeState.primary,
                    blurRadius: lit ? 18 : 12,
                    dy: 2,
                  )
                : null,
          ),
          // A thin scrim over the gradient, which is the only way to lift a
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
