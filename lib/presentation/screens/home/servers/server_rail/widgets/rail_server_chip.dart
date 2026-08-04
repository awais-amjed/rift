import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../common/squircle_avatar.dart';
import 'rail_unread_badge.dart';
import 'server_chip_menu.dart';

/// One server in the rail.
///
/// The selected server is ringed twice — a gap in the panel's own colour, then
/// the accent — so the ring reads as a halo around the chip rather than a
/// border drawn on it. Unselected chips sit at 85% opacity and come up to full
/// on hover, which is what makes the current server obvious in a long rail.
class RailServerChip extends StatefulWidget {
  final Server server;
  final bool isSelected;
  final int unreadCount;
  final VoidCallback onTap;

  const RailServerChip({
    super.key,
    required this.server,
    required this.isSelected,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  State<RailServerChip> createState() => _RailServerChipState();
}

class _RailServerChipState extends State<RailServerChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return ContextMenuRegion(
          contextMenu: ServerChipMenu(server: widget.server),
          child: Tooltip(
            message: widget.server.name,
            waitDuration: const Duration(milliseconds: 400),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                // The badge overhangs the chip's corner, so the stack can't clip.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      opacity: widget.isSelected || _hovered ? 1 : 0.85,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(K.radiusRailChip),
                          boxShadow: widget.isSelected
                              ? [
                                  BoxShadow(
                                    color: themeState.bgSecondary,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: themeState.primary.withValues(
                                      alpha: 0.8,
                                    ),
                                    spreadRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                        child: SquircleAvatar(
                          name: widget.server.name,
                          seed: widget.server.id,
                          imageUrl: widget.server.iconUrl,
                          size: K.serverRailChipSize,
                        ),
                      ),
                    ),
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
          ),
        );
      },
    );
  }
}
