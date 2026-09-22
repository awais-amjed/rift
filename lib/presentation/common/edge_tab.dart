import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';

/// Which edge a tab hangs off.
enum EdgeTabSide {
  left,
  right;

  bool get isLeft => this == EdgeTabSide.left;
}

/// The little tab that brings a hidden side panel back.
///
/// A real button, not a hot zone. The left sidebar used to slide out on hover,
/// which meant brushing the window edge on the way anywhere flung a panel over
/// the content — and it retracted on the first pixel out, so a menu opened
/// inside it took the pointer away and the panel vanished from under the menu.
/// Nothing here happens unless it is clicked.
///
/// Hover only widens it. That is the whole job of hover on a control: say that
/// pressing it would do something, not do the something.
class EdgeTab extends StatefulWidget {
  final EdgeTabSide side;
  final String tooltip;
  final VoidCallback onTap;

  const EdgeTab({
    super.key,
    required this.side,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<EdgeTab> createState() => _EdgeTabState();
}

class _EdgeTabState extends State<EdgeTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isLeft = widget.side.isLeft;
    final rounded = Radius.circular(K.radiusRow);

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Tooltip(
          message: widget.tooltip,
          waitDuration: K.tooltipDelay,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: AppMotion.state,
                width: _hovered ? 22 : 18,
                height: 72,
                decoration: BoxDecoration(
                  color: _hovered
                      ? themeState.bgTertiary
                      : themeState.bgSecondary,
                  // Square against the edge it grows out of, rounded on the
                  // side that faces the app.
                  borderRadius: BorderRadius.only(
                    topLeft: isLeft ? Radius.zero : rounded,
                    bottomLeft: isLeft ? Radius.zero : rounded,
                    topRight: isLeft ? rounded : Radius.zero,
                    bottomRight: isLeft ? rounded : Radius.zero,
                  ),
                  border: Border.all(color: themeState.borderPrimary),
                  boxShadow: AppShadows.edgeTab(
                    dark: themeState.isDarkTheme,
                    dx: isLeft ? 2 : -2,
                  ),
                ),
                // Points the way the panel will arrive from.
                child: Icon(
                  isLeft
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  size: 16,
                  color: _hovered
                      ? themeState.textPrimary
                      : themeState.textTertiary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
