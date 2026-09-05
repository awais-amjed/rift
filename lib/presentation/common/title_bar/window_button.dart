import 'package:flutter/material.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/custom_colors.dart';
import '../../../data/constants.dart';

/// One control in the title bar's right-hand cluster.
///
/// Small and rounded rather than the full-height slabs Windows draws — the bar
/// is chrome the user should stop noticing, so the buttons only appear on
/// hover. Close is the exception: it turns red, because it is the one control
/// here you can regret pressing.
class WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ThemeState themeState;

  /// Hover in the destructive colour instead of the neutral fill.
  final bool isClose;

  const WindowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.themeState,
    this.isClose = false,
  });

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isClose
        ? CustomColors.error
        : widget.themeState.bgHover;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 34,
            height: 26,
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(K.radiusRow),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered && widget.isClose
                  ? Colors.white
                  : widget.themeState.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
