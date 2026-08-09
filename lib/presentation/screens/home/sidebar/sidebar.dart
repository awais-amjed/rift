import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
import '../../../theme/app_motion.dart';
import 'widgets/sidebar_content.dart';
import 'widgets/sidebar_resize_handle.dart';

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
class Sidebar extends StatefulWidget {
  final double topPadding;

  const Sidebar({super.key, this.topPadding = 0});

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
    _showContent = context.read<AppCubit>().state.sidebarOpen;
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
    return BlocConsumer<AppCubit, AppState>(
      listenWhen: (prev, curr) => prev.sidebarOpen != curr.sidebarOpen,
      listener: (context, appState) {
        // Back in the tree before the opening animation runs, or there would be
        // nothing inside the panel while it widens.
        if (appState.sidebarOpen && !_showContent) {
          setState(() => _showContent = true);
        }
      },
      buildWhen: (prev, curr) =>
          prev.sidebarOpen != curr.sidebarOpen ||
          prev.sidebarWidth != curr.sidebarWidth,
      builder: (context, appState) {
        final windowWidth = MediaQuery.sizeOf(context).width;
        final width = SidebarSizing.clamp(
          _dragWidth ?? appState.sidebarWidth,
          windowWidth: windowWidth,
        );
        final full = width + K.sidebarResizeHandleWidth;

        return AnimatedContainer(
          // A drag is not a transition. Animating it would leave the panel a
          // frame or two behind the pointer, which reads as lag rather than
          // polish — so while the pointer is down, the width tracks it exactly.
          duration: _dragWidth != null ? Duration.zero : K.sidebarMotion,
          curve: AppMotion.panel,
          width: appState.sidebarOpen ? full : 0,
          onEnd: () {
            if (!appState.sidebarOpen && _showContent) {
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
                        AppPanel(
                          width: width,
                          child: SidebarContent(topPadding: widget.topPadding),
                        ),
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
