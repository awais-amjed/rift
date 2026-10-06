import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/network/network_cubit.dart';
import '../../../logic/cubits/server_reach/server_reach_cubit.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';
import '../app_mark.dart';
import '../status_chip.dart';
import 'update_chip.dart';
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

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
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

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
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
        const UpdateChip(),
        const _ConnectionChip(),
        WindowButton(
          icon: widget.pinned
              ? Icons.expand_less_rounded
              : Icons.push_pin_outlined,
          tooltip: widget.pinned ? 'Hide title bar' : 'Pin title bar',
          onTap: () =>
              widget.pinned ? widget.onHide?.call() : widget.onShow?.call(),
        ),
        WindowButton(
          icon: Icons.remove_rounded,
          tooltip: 'Minimize',
          onTap: () => windowManager.minimize(),
        ),
        WindowButton(
          icon: _isMaximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          tooltip: _isMaximized ? 'Restore' : 'Maximize',
          onTap: () => _isMaximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        WindowButton(
          icon: Icons.close_rounded,
          tooltip: 'Minimize to tray',
          onTap: () => windowManager.hide(),

          isClose: true,
        ),
      ],
    );
  }
}

/// One line about the connection beside the window controls, or nothing.
///
/// "No internet" first: with no network every server is out of reach, and
/// naming one of them would point at the wrong thing. Otherwise the selected
/// server, if it can't be reached. Never both — two chips saying one problem
/// twice reads as two problems.
class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip();

  @override
  Widget build(BuildContext context) {
    final networkDown = context.select<NetworkCubit, bool>(
      (c) => c.state.offline,
    );
    final showOffline = context.select<AppCubit, bool>(
      (c) => c.state.showOfflineChip,
    );
    final offline = networkDown && showOffline;
    final server = context.select<ServerReachCubit, String?>(
      (c) => c.state.unreachableName,
    );
    final chip = offline
        ? const StatusChip(
            icon: Icons.wifi_off_rounded,
            label: 'No internet',
            color: CustomColors.warning,
            tooltip:
                'This device is not connected to the internet. A server on '
                'your own network can still work; everything else waits until '
                'you are back online.',
          )
        : server != null
        ? StatusChip(
            icon: Icons.cloud_off_rounded,
            label: "Can't reach $server",
            color: CustomColors.error,
            tooltip:
                'Rift has lost its connection to this server and keeps '
                "trying. New messages and calls won't arrive until it is "
                'back.',
          )
        : null;
    if (chip == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      // A long server name ends in an ellipsis rather than pushing the window
      // controls off the bar.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: K.titleBarChipMaxWidth),
        child: chip,
      ),
    );
  }
}
