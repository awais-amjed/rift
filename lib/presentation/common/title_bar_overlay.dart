import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/app/app_cubit.dart';
import '../../logic/services/host_platform.dart';
import 'title_bar/app_title_bar.dart';

/// Wraps the entire app (above the Navigator) so the title bar always renders
/// on top of dialogs, sheets, and any other Navigator overlay.
///
/// An [Overlay] is used as the root so that [AppTitleBar]'s [Tooltip] widgets
/// can resolve [Overlay.of(context)] without error. Both [child] (the
/// Navigator) and [AppTitleBar] live inside the same [OverlayEntry] Stack, so
/// the title bar is painted last — above everything the Navigator renders.
class TitleBarOverlay extends StatefulWidget {
  final Widget child;

  const TitleBarOverlay({super.key, required this.child});

  @override
  State<TitleBarOverlay> createState() => _TitleBarOverlayState();
}

class _TitleBarOverlayState extends State<TitleBarOverlay> {
  // ValueNotifier instead of setState so the OverlayEntry rebuilds
  // independently without rebuilding the Overlay itself.
  final _hovering = ValueNotifier<bool>(false);

  static const double _height = K.titleBarHeight;
  static const double _hotZone = K.titleBarHotZoneHeight;

  late final OverlayEntry _entry = OverlayEntry(
    opaque: true,
    maintainState: true,
    builder: _buildEntry,
  );

  @override
  void didUpdateWidget(TitleBarOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the child subtree changes, ask the entry to rebuild.
    if (oldWidget.child != widget.child) _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _hovering.dispose();
    super.dispose();
  }

  Widget _buildEntry(BuildContext ctx) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (p, c) => p.titleBarVisible != c.titleBarVisible,
      builder: (context, appState) {
        final visible = appState.titleBarVisible;
        return ValueListenableBuilder<bool>(
          valueListenable: _hovering,
          builder: (_, hovering, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              // Navigator (routes + its own dialog overlay) sits below.
              widget.child,
              // Title bar is last in the Stack → always above dialogs.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                top: (visible || hovering) ? 0 : -_height,
                left: 0,
                right: 0,
                height: _height,
                child: AppTitleBar(
                  height: _height,
                  pinned: visible,
                  onHide: () {
                    context.read<AppCubit>().setTitleBarVisible(false);
                    _hovering.value = false;
                  },
                  onShow: () {
                    context.read<AppCubit>().setTitleBarVisible(true);
                    _hovering.value = false;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Not just web: a phone has its own status bar and no window to drag.
    if (!HostPlatform.drawsOwnWindowChrome) return widget.child;

    return MouseRegion(
      onHover: (e) {
        // Read current state directly — no rebuild needed here.
        final visible = context.read<AppCubit>().state.titleBarVisible;
        if (visible) return;
        final nearTop = e.localPosition.dy <= _hotZone;
        if (nearTop != _hovering.value) _hovering.value = nearTop;
      },
      onExit: (_) => _hovering.value = false,
      child: Overlay(
        // Clip.none so title-bar tooltips can paint below the 40 px zone.
        clipBehavior: Clip.none,
        initialEntries: [_entry],
      ),
    );
  }
}
