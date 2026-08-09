import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
import '../../../theme/app_shadows.dart';
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
    // The overlay isn't draggable — there is no gutter to grab beside it — but
    // it uses the width chosen while pinned, so unpinning doesn't resize the
    // thing you just sized.
    final width = SidebarSizing.clamp(
      context.watch<AppCubit>().state.sidebarWidth,
      windowWidth: MediaQuery.sizeOf(context).width,
    );

    return Stack(
      children: [
        // ── Sliding sidebar overlay ───────────────────────────
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          left: _hovered ? 0 : -width,
          top: 0,
          bottom: 0,
          width: width,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AppPanel(
              shadow: AppShadows.popover,
              child: SidebarContent(
                isPinned: false,
                topPadding: widget.topPadding,
              ),
            ),
          ),
        ),

        // ── Hot-zone strip on the left edge, with a visible handle ────
        if (!_hovered)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _hotZoneWidth,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 4,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.watch<ThemeCubit>().state.primary.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
