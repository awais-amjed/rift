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
class ComposerSendButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(K.composerControlRadius);

    return Tooltip(
      message: 'Send',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: radius,
        hoverColor: enabled ? Colors.transparent : themeState.bgHover,
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
            boxShadow: enabled
                ? AppShadows.accentGlow(
                    themeState.primary,
                    blurRadius: 12,
                    dy: 2,
                  )
                : null,
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
