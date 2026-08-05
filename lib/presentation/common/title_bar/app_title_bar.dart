import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_text.dart';
import '../app_mark.dart';
import 'window_button.dart';

/// The window's own chrome: brand mark on the left, window controls on the
/// right, everything between draggable.
///
/// It paints no background of its own when pinned — the canvas shows through,
/// so the bar reads as part of the workspace rather than a bar bolted to the
/// top of it. In overlay mode it takes a translucent fill, because there it is
/// floating over content and needs an edge.
class AppTitleBar extends StatefulWidget {
  final double height;

  /// Whether the bar is permanently pinned (vs. shown as a hover overlay).
  final bool pinned;

  /// Called when the user hides / unpins the bar.
  final VoidCallback? onHide;

  /// Called when the user pins the bar while in overlay mode.
  final VoidCallback? onShow;

  const AppTitleBar({
    super.key,
    this.height = K.titleBarHeight,
    this.pinned = true,
    this.onHide,
    this.onShow,
  });

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar>
    with WindowListener, TrayListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  // ── TrayListener ─────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'quit':
        windowManager.destroy();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        // The bar is mounted in the root Overlay, above the Navigator, so
        // nothing here inherits a Scaffold's Material. Without one there is no
        // `DefaultTextStyle` but the framework's error style, which is what
        // strikes the wordmark through with a double yellow underline. Painting
        // no surface of its own, so the fill below still shows through.
        return Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.pinned
                  ? Colors.transparent
                  : themeState.bgSecondary.withValues(alpha: 0.72),
            ),
            child: SizedBox(
              height: widget.height,
              child: Stack(
                children: [
                  // Draggable region covering the full bar, under the controls.
                  const Positioned.fill(
                    child: DragToMoveArea(child: SizedBox.expand()),
                  ),
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    child: _buildBrand(themeState),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: _buildControls(themeState),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBrand(ThemeState themeState) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppMark(),
        const SizedBox(width: 8),
        Text(
          'rift',
          style: AppText.row.copyWith(
            fontSize: 13,
            letterSpacing: 0.2,
            color: themeState.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildControls(ThemeState themeState) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        WindowButton(
          icon: widget.pinned
              ? Icons.expand_less_rounded
              : Icons.push_pin_outlined,
          tooltip: widget.pinned ? 'Hide title bar' : 'Pin title bar',
          onTap: () =>
              widget.pinned ? widget.onHide?.call() : widget.onShow?.call(),
          themeState: themeState,
        ),
        WindowButton(
          icon: Icons.remove_rounded,
          tooltip: 'Minimize',
          onTap: () => windowManager.minimize(),
          themeState: themeState,
        ),
        WindowButton(
          icon: _isMaximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          tooltip: _isMaximized ? 'Restore' : 'Maximize',
          onTap: () => _isMaximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
          themeState: themeState,
        ),
        WindowButton(
          icon: Icons.close_rounded,
          tooltip: 'Minimize to tray',
          onTap: () => windowManager.hide(),
          themeState: themeState,
          isClose: true,
        ),
      ],
    );
  }
}
