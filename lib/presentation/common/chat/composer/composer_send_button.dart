import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_shadows.dart';

/// The send button: a filled accent circle once there's something to send, a
/// muted ghost arrow otherwise. Its footprint never changes between the two
/// states — only the colours cross-fade — so the arrow doesn't hop as you type.
class ComposerSendButton extends StatelessWidget {
  static const double _circleSize = 32;

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
    return Tooltip(
      message: 'Send',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        customBorder: const CircleBorder(),
        hoverColor: enabled ? Colors.transparent : themeState.bgHover,
        child: SizedBox(
          width: K.composerControlSize,
          height: K.composerControlSize,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _circleSize,
              height: _circleSize,
              decoration: BoxDecoration(
                // Enabled, this is the app's one action gradient, lit from
                // below — the single loudest control on the screen, which is
                // right for the only irreversible thing in the composer.
                gradient: enabled ? themeState.actionGradient : null,
                shape: BoxShape.circle,
                boxShadow: enabled
                    ? AppShadows.accentGlow(
                        themeState.primary,
                        blurRadius: 12,
                        dy: 2,
                      )
                    : null,
              ),
              child: Center(
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: K.composerIconSize,
                  color: enabled
                      ? themeState.onPrimary
                      : themeState.textQuaternary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
