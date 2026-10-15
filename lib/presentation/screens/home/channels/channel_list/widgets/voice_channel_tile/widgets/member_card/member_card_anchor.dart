import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../responsive/shell_scope.dart';
import '../../../../../../../../theme/app_motion.dart';
import '../../../../../../profile/person/show_person_profile.dart';
import 'member_card.dart';
import 'member_card_layout.dart';

/// A roster row that opens its person's card on a click ([MemberCard]):
/// quick controls, a message box, and — while they have a screen up — a
/// button to watch it, from a call you are not in yet if need be.
///
/// A click, not a hover: a card that sprang open under a pointer passing down
/// the sidebar would cover the rows below it. A click also works on a phone.
/// Their profile and everything else stay in the right-click menu.
///
/// The card hangs off the row's right edge, out over the page — below the row
/// on a phone, where there is nothing to the right — kept inside the window
/// ([MemberCardLayout]). A click anywhere else, the row again, Escape or a
/// scroll of the sidebar closes it.
class MemberCardAnchor extends StatefulWidget {
  /// Whether the row's person is sharing a screen, which puts a Watch button
  /// on the card.
  final bool sharing;
  final String userId;
  final String name;

  /// The voice channel the row is in.
  final String channelId;

  /// Watch their stream, joining the call first if need be.
  final VoidCallback? onWatch;

  final Widget child;

  const MemberCardAnchor({
    super.key,
    required this.sharing,
    required this.userId,
    required this.name,
    required this.channelId,
    required this.onWatch,
    required this.child,
  });

  @override
  State<MemberCardAnchor> createState() => _MemberCardAnchorState();
}

class _MemberCardAnchorState extends State<MemberCardAnchor> {
  final _portal = OverlayPortalController();

  /// The sidebar's scroll, listened to while the card is open: the card is
  /// placed once, where the row was, and a row scrolled away from it would
  /// leave it pointing at somebody else.
  ScrollPosition? _scroll;

  /// The row and the card are one region, so a click on either is not a
  /// click outside.
  final _tapGroup = Object();

  @override
  void dispose() {
    _scroll?.removeListener(_close);
    super.dispose();
  }

  void _close() {
    _scroll?.removeListener(_close);
    _scroll = null;
    if (mounted && _portal.isShowing) _portal.hide();
  }

  void _toggle() {
    if (_portal.isShowing) {
      _close();
    } else {
      _scroll = Scrollable.maybeOf(context)?.position?..addListener(_close);
      // Their roles are read for the rows on screen, which a call's roster
      // is not one of.
      context.read<ServerMembersCubit>().resolve([widget.userId]);
      _portal.show();
    }
  }

  /// The row's box in [overlay]'s coordinates, or null before it has one.
  Rect? _rowIn(BuildContext overlay) {
    final row = context.findRenderObject() as RenderBox?;
    final ground = overlay.findRenderObject() as RenderBox?;
    if (row == null || ground == null || !row.hasSize) return null;
    return row.localToGlobal(Offset.zero, ancestor: ground) & row.size;
  }

  /// From the row's context, not the card's: the card is gone by the time
  /// the dialog looks for a navigator.
  void _profile() {
    _close();
    showMemberProfile(context, userId: widget.userId, name: widget.name);
  }

  void _watch() {
    _close();
    widget.onWatch?.call();
  }

  @override
  Widget build(BuildContext context) {
    final below = context.layoutMode.isCompact;
    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: widget.child,
      ),
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        final rect = _rowIn(Overlay.of(overlayContext).context);
        if (rect == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: MemberCardLayout(anchor: rect, below: below),
            child: TapRegion(
              groupId: _tapGroup,
              onTapOutside: (_) => _close(),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _close,
                },
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
                  child: MemberCard(
                    userId: widget.userId,
                    name: widget.name,
                    channelId: widget.channelId,
                    onProfile: _profile,
                    onClose: _close,
                    // Only while their share is up: the card stays open
                    // when it ends, and the button goes.
                    onWatch: widget.sharing && widget.onWatch != null
                        ? _watch
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: TapRegion(groupId: _tapGroup, child: row),
    );
  }
}
