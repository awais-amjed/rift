import 'package:material_ui/material_ui.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';
import 'app_modal_header.dart';

/// One icon button in a modal's header: the close, or an action beside it.
/// 32px square, the row radius, tertiary ink.
class AppModalHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Turns the icon, in whole turns — a refresh's arrow (`RefreshButton`).
  final Animation<double>? turns;

  const AppModalHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.turns,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final glyph = Icon(
      icon,
      color: themeState.textTertiary,
      size: K.iconButton,
    );
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: switch (turns) {
        final turns? => RotationTransition(turns: turns, child: glyph),
        null => glyph,
      },
      constraints: const BoxConstraints.tightFor(
        width: AppModalHeader.buttonSize,
        height: AppModalHeader.buttonSize,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(K.radiusRow),
        ),
      ),
    );
  }
}
