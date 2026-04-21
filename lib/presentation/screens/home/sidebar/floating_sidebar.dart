import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import 'widgets/sidebar_content.dart';

/// Shown when the sidebar is unpinned. Renders an invisible hot-zone on the
/// left edge; hovering it slides the sidebar in as a shadow overlay.
/// A chevron-right button inside pins the sidebar back permanently.
class FloatingSidebar extends StatefulWidget {
  /// Extra top padding — pass the title bar height when the appbar is hidden.
  final double topPadding;

  const FloatingSidebar({super.key, this.topPadding = 0});

  // ...existing code...
  @override
  State<FloatingSidebar> createState() => _FloatingSidebarState();
}

class _FloatingSidebarState extends State<FloatingSidebar> {
  bool _hovered = false;

  static const double _hotZoneWidth = 8;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Sliding sidebar overlay ───────────────────────────
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          left: _hovered ? 0 : -K.sidebarWidth,
          top: 0,
          bottom: 0,
          width: K.sidebarWidth,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: SidebarContent(
              isPinned: false,
              topPadding: widget.topPadding,
            ),
          ),
        ),

        // ── Invisible hot-zone strip on the left edge ─────────
        if (!_hovered)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _hotZoneWidth,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}
