import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/custom_colors.dart';

/// Custom draggable title bar with minimize, maximize and close controls.
/// Drop it anywhere at the top of a screen — it is not a [PreferredSizeWidget]
/// so it fits naturally inside a [Column] or a [Stack].
class AppTitleBar extends StatefulWidget {
  /// Optional title shown in the centre / left of the bar.
  final String? title;

  /// Height of the bar. Defaults to 40.
  final double height;

  /// Whether the bar is permanently pinned (vs. shown as a hover overlay).
  final bool pinned;

  /// Called when the user clicks the chevron to hide / unpin the bar.
  final VoidCallback? onHide;

  /// Called when the user clicks the pin button while in overlay mode.
  final VoidCallback? onShow;

  const AppTitleBar({
    super.key,
    this.title,
    this.height = 40,
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
        return SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              // Draggable region covering the full bar
              const Positioned.fill(
                child: DragToMoveArea(child: SizedBox.expand()),
              ),

              // Left button: hide when pinned, pin when in overlay mode
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _WindowButton(
                  icon: widget.pinned
                      ? Icons.expand_less_rounded
                      : Icons.push_pin_outlined,
                  tooltip: widget.pinned ? 'Hide title bar' : 'Pin title bar',
                  onTap: () => widget.pinned
                      ? widget.onHide?.call()
                      : widget.onShow?.call(),
                  themeState: themeState,
                ),
              ),

              // Title (centred)
              if (widget.title != null)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      widget.title!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: themeState.textTertiary,
                      ),
                    ),
                  ),
                ),

              // Window control buttons (right side)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WindowButton(
                      icon: Icons.remove_rounded,
                      tooltip: 'Minimize',
                      onTap: () => windowManager.minimize(),
                      themeState: themeState,
                    ),
                    _WindowButton(
                      icon: _isMaximized
                          ? Icons.filter_none_rounded
                          : Icons.crop_square_rounded,
                      tooltip: _isMaximized ? 'Restore' : 'Maximize',
                      onTap: () => _isMaximized
                          ? windowManager.unmaximize()
                          : windowManager.maximize(),
                      themeState: themeState,
                    ),
                    _WindowButton(
                      icon: Icons.minimize_rounded,
                      tooltip: 'Minimize to tray',
                      onTap: () => windowManager.hide(),
                      themeState: themeState,
                      isClose: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ThemeState themeState;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.themeState,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isClose
        ? CustomColors.error
        : widget.themeState.bgHover;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: double.infinity,
            color: _hovered ? hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 16,
              color: _hovered && widget.isClose
                  ? Colors.white
                  : widget.themeState.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
