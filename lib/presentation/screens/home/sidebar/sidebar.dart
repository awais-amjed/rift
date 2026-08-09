import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
import 'widgets/sidebar_content.dart';
import 'widgets/sidebar_resize_handle.dart';

/// The pinned sidebar, and the strip you drag to resize it. Renders nothing
/// when unpinned — [FloatingSidebar] takes over there.
///
/// The width is held locally while the pointer is down and only written to
/// [AppCubit] when the drag ends. Emitting per frame would be a persisted
/// write per frame, since AppCubit is hydrated, to store a value that is about
/// to change again anyway.
class Sidebar extends StatefulWidget {
  final double topPadding;

  const Sidebar({super.key, this.topPadding = 0});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  /// Non-null only mid-drag; otherwise the stored width is the truth.
  double? _dragWidth;

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
      buildWhen: (prev, curr) =>
          prev.isPinned != curr.isPinned ||
          prev.sidebarWidth != curr.sidebarWidth,
      builder: (context, appState) {
        if (!appState.isPinned) return const SizedBox.shrink();

        final windowWidth = MediaQuery.sizeOf(context).width;
        final width = SidebarSizing.clamp(
          _dragWidth ?? appState.sidebarWidth,
          windowWidth: windowWidth,
        );

        return Row(
          children: [
            AppPanel(
              width: width,
              child: SidebarContent(
                isPinned: true,
                topPadding: widget.topPadding,
              ),
            ),
            SidebarResizeHandle(
              onDrag: (delta) =>
                  _onDrag(delta, appState.sidebarWidth, windowWidth),
              onDragEnd: _onDragEnd,
              onReset: _reset,
            ),
          ],
        );
      },
    );
  }
}
