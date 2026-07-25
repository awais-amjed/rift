import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../server_selector/widgets/server_list_view.dart';

/// Anchored popover for switching between joined servers, opened from the
/// sidebar's server row. Replaces the full-screen dialog for the common switch
/// action; adding / joining / creating still uses [ServerSelectorDialog] via
/// the [onAddServer] callback.
class ServerSwitcherPopover {
  const ServerSwitcherPopover._();

  /// Shows the popover anchored to [anchorContext]'s widget (the server row).
  static void show(
    BuildContext anchorContext, {
    required VoidCallback onAddServer,
  }) {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;

    // Anchor rect in the overlay's coordinate space.
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchor = topLeft & box.size;

    final serverCubit = anchorContext.read<ServerCubit>();
    final themeCubit = anchorContext.read<ThemeCubit>();
    final notificationsCubit = anchorContext.read<ServerNotificationsCubit>();
    final overlay = Overlay.of(anchorContext);

    late OverlayEntry entry;
    var removed = false;
    void dismiss() {
      if (removed) return;
      removed = true;
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: serverCubit),
          BlocProvider.value(value: themeCubit),
          BlocProvider.value(value: notificationsCubit),
        ],
        child: _ServerSwitcherOverlay(
          anchor: anchor,
          overlaySize: overlayBox.size,
          onDismiss: dismiss,
          onAddServer: () {
            dismiss();
            onAddServer();
          },
        ),
      ),
    );
    overlay.insert(entry);
  }
}

class _ServerSwitcherOverlay extends StatefulWidget {
  final Rect anchor;
  final Size overlaySize;
  final VoidCallback onDismiss;
  final VoidCallback onAddServer;

  const _ServerSwitcherOverlay({
    required this.anchor,
    required this.overlaySize,
    required this.onDismiss,
    required this.onAddServer,
  });

  @override
  State<_ServerSwitcherOverlay> createState() => _ServerSwitcherOverlayState();
}

class _ServerSwitcherOverlayState extends State<_ServerSwitcherOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    // Popover sits just below the server row, left-aligned to it, and is at
    // least as wide as the row (up to a sensible cap). Height is capped to the
    // space below the anchor so it scrolls rather than overflowing.
    const gap = 6.0;
    final width = widget.anchor.width.clamp(240.0, 340.0);
    final left = widget.anchor.left.clamp(
      8.0,
      (widget.overlaySize.width - width - 8).clamp(8.0, double.infinity),
    );
    final top = widget.anchor.bottom + gap;
    final maxHeight = (widget.overlaySize.height - top - 12).clamp(120.0, 520.0);

    return Stack(
      children: [
        // Tap-outside barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: FadeTransition(
            opacity: _controller,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
              ),
              alignment: Alignment.topLeft,
              child: Material(
                color: themeState.bgSecondary,
                elevation: 12,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: themeState.borderPrimary),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Text(
                          'SWITCH SERVER',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: themeState.textQuaternary,
                          ),
                        ),
                      ),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                            child: ServerListView(
                              onAddServer: widget.onAddServer,
                              onClose: widget.onDismiss,
                            ),
                          ),
                        ),
                      ),
                    ],
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
