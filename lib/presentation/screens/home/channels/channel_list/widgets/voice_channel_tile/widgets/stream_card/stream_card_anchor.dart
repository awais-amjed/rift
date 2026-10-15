import 'package:flutter/material.dart';

import '../../../../../../../../responsive/shell_scope.dart';
import '../../../../../../../../theme/app_motion.dart';
import 'stream_card.dart';

/// A roster row that, while its person has a screen up, opens a card on a
/// click with a button to watch it, so a stream can be opened from a call you
/// are not in yet.
///
/// A click, not a hover: a person's row otherwise does nothing on a click,
/// and a card that sprang open under a pointer passing down the sidebar
/// would cover the rows below it. A click also works on a phone.
///
/// The card hangs off the row's right edge, out over the page — below the row
/// on a phone, where there is nothing to the right. A click anywhere else, or
/// the row again, closes it.
class StreamCardAnchor extends StatefulWidget {
  /// Whether the row's person is sharing a screen. Nothing happens when not.
  final bool sharing;
  final String userId;
  final String name;

  /// The voice channel the row is in.
  final String channelId;

  /// Watch their stream, joining the call first if need be.
  final VoidCallback? onWatch;

  final Widget child;

  const StreamCardAnchor({
    super.key,
    required this.sharing,
    required this.userId,
    required this.name,
    required this.channelId,
    required this.onWatch,
    required this.child,
  });

  @override
  State<StreamCardAnchor> createState() => _StreamCardAnchorState();
}

class _StreamCardAnchorState extends State<StreamCardAnchor> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  /// The row and the card are one region, so a click on either is not a
  /// click outside.
  final _tapGroup = Object();

  bool get _enabled => widget.sharing && widget.onWatch != null;

  @override
  void didUpdateWidget(StreamCardAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Their share ended with the card open.
    if (!_enabled && _portal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
  }

  void _close() {
    if (mounted && _portal.isShowing) _portal.hide();
  }

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else if (_enabled) {
      _portal.show();
    }
  }

  void _watch() {
    _close();
    widget.onWatch?.call();
  }

  @override
  Widget build(BuildContext context) {
    final below = context.layoutMode.isCompact;
    Widget row = widget.child;
    if (_enabled) {
      row = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: row,
        ),
      );
    }
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: below
                ? Alignment.bottomCenter
                : Alignment.centerRight,
            followerAnchor: below ? Alignment.topCenter : Alignment.centerLeft,
            offset: below ? const Offset(0, 6) : const Offset(12, 0),
            child: TapRegion(
              groupId: _tapGroup,
              onTapOutside: (_) => _close(),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: AppMotion.state,
                curve: AppMotion.arrive,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: below
                        ? Offset(0, -6 * (1 - t))
                        : Offset(-6 * (1 - t), 0),
                    child: child,
                  ),
                ),
                child: StreamCard(
                  userId: widget.userId,
                  name: widget.name,
                  channelId: widget.channelId,
                  onWatch: _watch,
                ),
              ),
            ),
          ),
        ),
        child: TapRegion(groupId: _tapGroup, child: row),
      ),
    );
  }
}
