import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_motion.dart';
import 'context_menu/context_menu_watcher.dart';

/// A small panel that stands up over [anchor] while the pointer is on
/// either of them: a volume's track over its speaker.
///
/// Drawn in the overlay, above whatever is round the anchor, so it takes no
/// room from the controls beside it (a track sliding out sideways pushed
/// them along) and is not clipped by the card or tile it rises out of. It
/// closes [AppMotion.linger] after the pointer leaves both, so a pointer
/// slipping off a thin track does not shut it, and never in the middle of a
/// drag.
///
/// Hover has no finger: [RisingPanelState.pin] opens it from a tap, and a
/// tap anywhere else closes it again.
///
/// Whatever fades its controls when the pointer leaves hears it open and
/// close through [ContextMenuWatcher], as it does a menu: the pointer on the
/// panel is off the controls, as far as they can tell.
class RisingPanel extends StatefulWidget {
  final Widget anchor;
  final WidgetBuilder panel;

  /// Between the anchor and the panel, and part of the panel's hover, so the
  /// pointer crossing it does not leave.
  final double gap;

  const RisingPanel({
    super.key,
    required this.anchor,
    required this.panel,
    this.gap = 6,
  });

  @override
  State<RisingPanel> createState() => RisingPanelState();
}

class RisingPanelState extends State<RisingPanel>
    with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _shown;
  late final CurvedAnimation _fade;
  Timer? _closing;
  ContextMenuWatcher? _watcher;

  bool _overAnchor = false;
  bool _overPanel = false;
  bool _pressed = false;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _shown = AnimationController(vsync: this, duration: AppMotion.react);
    _fade = CurvedAnimation(parent: _shown, curve: AppMotion.settle);
  }

  @override
  void dispose() {
    _closing?.cancel();
    _fade.dispose();
    _shown.dispose();
    // After the frame: this goes while the tree is being torn down, when
    // whoever is told cannot rebuild.
    final watcher = _watcher;
    if (watcher != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => watcher.onClosed());
    }
    super.dispose();
  }

  /// Whether it is up, or on its way.
  bool get isOpen =>
      _portal.isShowing && _shown.status != AnimationStatus.reverse;

  /// Opened by a tap, where there is no hover: it stays until a tap lands
  /// somewhere else.
  void pin() {
    _pinned = true;
    _update();
  }

  void _update() {
    _closing?.cancel();
    if (_overAnchor || _overPanel || _pressed || _pinned) return _open();
    _closing = Timer(AppMotion.linger, _close);
  }

  void _open() {
    if (!_portal.isShowing) {
      _portal.show();
      _watcher = ContextMenuWatcher.maybeOf(context)?..onOpened();
    }
    _shown.forward();
  }

  void _close() {
    if (!mounted || !_portal.isShowing) return;
    _shown.reverse().whenCompleteOrCancel(() {
      if (!mounted || !_shown.isDismissed || !_portal.isShowing) return;
      _portal.hide();
      _watcher?.onClosed();
      _watcher = null;
    });
  }

  void _unpin() {
    if (!_pinned) return;
    _pinned = false;
    _update();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _unpin(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            child: TapRegion(
              groupId: this,
              onTapOutside: (_) => _unpin(),
              child: MouseRegion(
                onEnter: (_) {
                  _overPanel = true;
                  _update();
                },
                onExit: (_) {
                  _overPanel = false;
                  _update();
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) {
                    _pressed = true;
                    _update();
                  },
                  onPointerUp: (_) => _released(),
                  onPointerCancel: (_) => _released(),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: widget.gap),
                    child: FadeTransition(
                      opacity: _fade,
                      child: widget.panel(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: MouseRegion(
            onEnter: (_) {
              _overAnchor = true;
              _update();
            },
            onExit: (_) {
              _overAnchor = false;
              _update();
            },
            child: widget.anchor,
          ),
        ),
      ),
    );
  }

  void _released() {
    _pressed = false;
    _update();
  }
}
