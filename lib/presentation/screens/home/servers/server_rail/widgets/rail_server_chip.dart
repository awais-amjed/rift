import 'package:flutter/material.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/constants.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../common/squircle_avatar.dart';
import '../../../../../theme/app_motion.dart';
import '../../../../../theme/theme_context.dart';
import 'rail_unread_badge.dart';
import 'server_chip_menu.dart';

/// One server in the rail.
///
/// The selected server wears a halo: a ring of accent held off the chip by a
/// gap in the panel's own colour, so it reads as something around the chip
/// rather than a slab behind it. Unselected chips sit at 85% opacity and come
/// up to full on hover, which is what makes the current server obvious in a
/// long rail.
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

/// Width of the accent ring, and of the gap between it and the chip. Equal by
/// design; [_haloExtent] is how far the pair reaches past the chip's edge.
const double _haloRing = 2;
const double _haloGap = 2;
const double _haloExtent = _haloRing + _haloGap;

class _RailServerChipState extends State<RailServerChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      contextMenu: ServerChipMenu(server: widget.server),
      child: Tooltip(
        message: widget.server.name,
        waitDuration: K.tooltipDelay,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            // Both the halo and the badge overhang the chip, so the stack
            // can't clip — and neither may size it, or picking a server
            // would shift the whole rail.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.isSelected)
                  const Positioned(
                    left: -_haloExtent,
                    top: -_haloExtent,
                    right: -_haloExtent,
                    bottom: -_haloExtent,
                    child: _SelectionHalo(),
                  ),
                AnimatedOpacity(
                  duration: AppMotion.state,
                  opacity: widget.isSelected || _hovered ? 1 : 0.85,
                  child: SquircleAvatar(
                    name: widget.server.name,
                    seed: widget.server.id,
                    imageUrl: widget.server.iconUrl,
                    size: K.serverRailChipSize,
                    // Stated rather than left to the avatar's size/3, so
                    // the halo's corners can be derived from the same
                    // number the chip is actually drawn with.
                    radius: K.radiusRailChip,
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
  }
}

/// The ring around the selected chip, drawn behind it.
///
/// Two filled squircles rather than a border and a shadow: the gap has to be
/// opaque, or the accent shows through it and the whole thing collapses back
/// into a slab behind the icon. Each corner radius steps out with its box, so
/// the ring stays an even distance from the chip the whole way round instead
/// of pinching at the corners.
class _SelectionHalo extends StatelessWidget {
  const _SelectionHalo();

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: themeState.primary.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(K.radiusRailChip + _haloExtent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_haloRing),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: themeState.bgSecondary,
            borderRadius: BorderRadius.circular(K.radiusRailChip + _haloGap),
          ),
        ),
      ),
    );
  }
}
