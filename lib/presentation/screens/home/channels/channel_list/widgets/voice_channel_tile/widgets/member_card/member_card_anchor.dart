import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../responsive/shell_scope.dart';
import '../../../../../../../../theme/app_motion.dart';
import '../../../../../../profile/person/show_person_profile.dart';
import 'member_card.dart';
import 'member_card_layout.dart';

/// A person's row that opens their card on a click ([MemberCard]): quick
/// controls, a message box, and — while they have a screen up — a button to
/// watch it, from a call you are not in yet if need be. Rows in a voice
/// channel's roster and in the members sidebar both open it.
///
/// A click, not a hover: a card that sprang open under a pointer passing down
/// the sidebar would cover the rows below it. A click also works on a phone.
/// Everything else stays in the right-click menu.
///
/// The card hangs off the row's [side], out over the page — below the row on
/// a phone, where there is nothing beside it — kept inside the window
/// ([MemberCardLayout]). A click anywhere else, the row again, Escape or a
/// scroll of the sidebar closes it.
class MemberCardAnchor extends StatefulWidget {
  /// Whether the row's person is sharing a screen, which puts a Watch button
  /// on the card. Null to have the card work it out, as for [channelId].
  final bool? sharing;
  final String userId;
  final String name;

  /// The voice channel the row is in, or null when the row is not in one —
  /// the members sidebar — and the card looks up where they are.
  final String? channelId;

  /// Watch their stream in this voice channel, joining the call first if
  /// need be.
  final ValueChanged<String>? onWatch;

  /// Which side of the row the card opens on, away from the window edge the
  /// row's sidebar sits against. Below on a phone, whatever this says.
  final MemberCardSide side;

  /// The row, made clickable here.
  final Widget? child;

  /// The row, for one that draws its own press — an [InkWell] — and is
  /// handed what to call for it. A tap detector round a well would lose the
  /// tap to it.
  final Widget Function(VoidCallback open)? builder;

  const MemberCardAnchor({
    super.key,
    this.sharing,
    required this.userId,
    required this.name,
    this.channelId,
    required this.onWatch,
    this.side = MemberCardSide.right,
    this.child,
    this.builder,
  }) : assert((child == null) != (builder == null));

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

  void _watch(String channelId) {
    _close();
    widget.onWatch?.call(channelId);
  }

  @override
  Widget build(BuildContext context) {
    final side = context.layoutMode.isCompact
        ? MemberCardSide.below
        : widget.side;
    final row =
        widget.builder?.call(_toggle) ??
        MouseRegion(
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
            delegate: MemberCardLayout(anchor: rect, side: side),
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
                      offset: switch (side) {
                        MemberCardSide.right => Offset(-6 * (1 - t), 0),
                        MemberCardSide.left => Offset(6 * (1 - t), 0),
                        MemberCardSide.below => Offset(0, -6 * (1 - t)),
                      },
                      child: child,
                    ),
                  ),
                  child: MemberCard(
                    userId: widget.userId,
                    name: widget.name,
                    channelId: widget.channelId,
                    sharing: widget.sharing,
                    onProfile: _profile,
                    onClose: _close,
                    onWatch: widget.onWatch == null ? null : _watch,
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
