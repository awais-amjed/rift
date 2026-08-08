import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import 'rail_unread_badge.dart';

/// A rail slot holding an icon rather than an identity — Home, add-server,
/// settings.
///
/// Selected slots take an accent wash with an inset ring; unselected ones are
/// invisible until hovered, so the rail reads as a column of servers with
/// controls rather than a toolbar.
class RailChipButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isSelected;

  /// Draw a permanent hairline ring instead of nothing at rest — used by
  /// add-server, which has to be findable on an empty rail.
  final bool ghostRing;

  /// Unread count riding on the corner, as on a server chip. Home uses it for
  /// central DMs; the control slots leave it at zero.
  final int unreadCount;

  const RailChipButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isSelected = false,
    this.ghostRing = false,
    this.unreadCount = 0,
  });

  @override
  State<RailChipButton> createState() => _RailChipButtonState();
}

class _RailChipButtonState extends State<RailChipButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final Color background;
        if (widget.isSelected) {
          background = themeState.primary.withValues(alpha: 0.12);
        } else if (_hovered) {
          background = themeState.bgHover;
        } else {
          background = Colors.transparent;
        }

        final Color? ringColor = widget.isSelected
            ? themeState.primary.withValues(alpha: 0.3)
            : (widget.ghostRing ? themeState.borderElevated : null);

        return Tooltip(
          message: widget.tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              // The badge overhangs the chip and must not size it, or unread
              // news would shift the rail — same rule as a server chip.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: K.serverRailChipSize,
                    height: K.serverRailChipSize,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(K.radiusRailChip),
                      border: ringColor == null
                          ? null
                          : Border.all(color: ringColor),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 19,
                      color: widget.isSelected
                          ? themeState.accentBright
                          : themeState.textTertiary,
                    ),
                  ),
                  // Not while selected: you're looking at the list, which
                  // badges each conversation itself.
                  if (widget.unreadCount > 0 && !widget.isSelected)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: RailUnreadBadge(count: widget.unreadCount),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
