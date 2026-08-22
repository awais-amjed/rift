import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_shadows.dart';
import 'widgets/sidebar_content.dart';
import 'widgets/sidebar_resize_handle.dart';
import '../../../responsive/shell_scope.dart';

/// The left sidebar, and the strip you drag to resize it.
///
/// Stays mounted while hidden and animates its width to nothing, because a
/// widget that has been removed from the tree can't animate away — hiding used
/// to be a hard cut for exactly that reason. Once the close has finished the
/// contents are dropped, so a hidden sidebar isn't an invisible copy of itself
/// rebuilding for nobody. [SidebarTab] is what brings it back.
///
/// The width is held locally while the pointer is down and only written to
/// [AppCubit] when the drag ends. Emitting per frame would be a persisted write
/// per frame, since AppCubit is hydrated, to store a value that is about to
/// change again anyway.
///
/// [open] is passed in rather than read from [AppCubit] because where this is
/// mounted decides what openness means — a saved preference while docked, and
/// throwaway drawer state while overlaid. See `ShellScope`.
class Sidebar extends StatefulWidget {
  final double topPadding;

  /// Whether the panel is showing. Animating, not mounting: see the class doc.
  final bool open;

  /// Floating above the content rather than sitting beside it. Takes a shadow,
  /// may run wider relative to the window, and drops the resize handle —
  /// there is nothing beside it to trade width with. On a phone it is also
  /// flush against the screen edge, square there and rounded only on the side
  /// facing the content, the way a sheet that slid in from off-screen would
  /// be.
  final bool floating;

  const Sidebar({
    super.key,
    required this.open,
    this.topPadding = 0,
    this.floating = false,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  /// Non-null only mid-drag; otherwise the stored width is the truth.
  double? _dragWidth;

  /// Whether the contents are built. Dropped once a close has finished — and
  /// seeded from the launch state, because starting unpinned runs no animation
  /// at all, so there would be no `onEnd` to drop them on.
  late bool _showContent;

  @override
  void initState() {
    super.initState();
    _showContent = widget.open;
  }

  @override
  void didUpdateWidget(Sidebar old) {
    super.didUpdateWidget(old);
    // Back in the tree before the opening animation runs, or there would be
    // nothing inside the panel while it widens.
    if (widget.open && !_showContent) {
      setState(() => _showContent = true);
    }
  }

  void _onDrag(double delta, double stored, double windowWidth) {
    setState(() {
      // Clamped every frame, so the panel stops dead at the bounds instead of
      // the pointer running on and the sidebar snapping back later.
      _dragWidth = SidebarSizing.clamp(
        (_dragWidth ?? stored) + delta,
        windowWidth: windowWidth,
      );
    });
  }

  void _onDragEnd() {
    final width = _dragWidth;
    if (width != null) context.read<AppCubit>().setSidebarWidth(width);
    setState(() => _dragWidth = null);
  }

  void _reset() {
    setState(() => _dragWidth = null);
    context.read<AppCubit>().setSidebarWidth(K.sidebarWidth);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (prev, curr) => prev.sidebarWidth != curr.sidebarWidth,
      builder: (context, appState) {
        final mode = context.layoutMode;
        final gutter = mode.panelGutter;
        final windowWidth = MediaQuery.sizeOf(context).width;
        final width = SidebarSizing.clamp(
          _dragWidth ?? appState.sidebarWidth,
          windowWidth: windowWidth,
          overlay: widget.floating,
        );
        // Floating, the gutter is on both sides and the handle is gone, so the
        // panel plus its gutters is all there is to reserve — and on a phone
        // there are no gutters, so it is just the panel.
        final full = widget.floating
            ? width + gutter * 2
            : width + K.sidebarResizeHandleWidth;

        return AnimatedContainer(
          // A drag is not a transition. Animating it would leave the panel a
          // frame or two behind the pointer, which reads as lag rather than
          // polish — so while the pointer is down, the width tracks it exactly.
          duration: _dragWidth != null ? Duration.zero : K.sidebarMotion,
          curve: AppMotion.panel,
          width: widget.open ? full : 0,
          onEnd: () {
            if (!widget.open && _showContent) {
              setState(() => _showContent = false);
            }
          },
          child: !_showContent
              ? const SizedBox.shrink()
              : ClipRect(
                  child: OverflowBox(
                    // Pinned to the right edge, so a closing sidebar slides out
                    // to the left behind the content rather than being squeezed
                    // to nothing — and its rows keep their real width the whole
                    // way, instead of laying out at 3px and overflowing on the
                    // way past.
                    alignment: Alignment.centerRight,
                    minWidth: full,
                    maxWidth: full,
                    child: Row(
                      children: [
                        if (widget.floating) SizedBox(width: gutter),
                        AppPanel(
                          width: width,
                          shadow: widget.floating
                              ? AppShadows.overlayPane
                              : null,
                          // Square against the screen edge it is pinned to,
                          // rounded on the edge the content is behind — the
                          // shape a sheet that slid in from off-screen has.
                          borderRadius:
                              widget.floating && !mode.panelsAreIslands
                              ? const BorderRadius.horizontal(
                                  right: Radius.circular(K.radiusPanel),
                                )
                              : null,
                          child: SidebarContent(topPadding: widget.topPadding),
                        ),
                        if (widget.floating)
                          SizedBox(width: gutter)
                        else
                          SidebarResizeHandle(
                            onDrag: (delta) => _onDrag(
                              delta,
                              appState.sidebarWidth,
                              windowWidth,
                            ),
                            onDragEnd: _onDragEnd,
                            onReset: _reset,
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
