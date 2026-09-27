import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/enums/dm_link_state.dart';
import '../../../../../data/enums/dm_policy.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/chat/composer_notice.dart';
import '../../../../common/chat/time_out_gate.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'dm_request_banner.dart';

/// What sits under a server DM: the composer, or why there isn't one.
///
/// In the order the server would refuse a message, so the reason shown is the
/// one that would have been given:
///
///   * a time-out — nothing we say goes anywhere;
///   * our own block — say so, and offer to undo it;
///   * a request we sent that is still waiting — one message until they
///     answer, which we have already sent;
///   * nothing between us yet and their setting is "no one new".
///
/// A request *to* us keeps the composer and puts [DmRequestBanner] over it.
class DmComposerSlot extends StatelessWidget {
  final DmState state;
  final Widget composer;

  const DmComposerSlot({
    super.key,
    required this.state,
    required this.composer,
  });

  @override
  Widget build(BuildContext context) {
    final peerId = state.openPeerId;
    final name = state.openPeerName ?? 'They';
    final until = context.select<ServerCubit, DateTime?>(
      (c) => c.state.selectedServer?.user?.timedOutUntil,
    );
    if (peerId == null) return composer;

    final Widget slot;
    if (state.blockedIds.contains(peerId)) {
      slot = ComposerNotice(
        icon: Icons.block_rounded,
        text: 'You blocked $name. They can\'t message or call you here.',
        actionLabel: 'Unblock',
        onAction: () => unawaited(
          context.read<DmCubit>().setBlocked(peerId, blocked: false),
        ),
      );
    } else if (state.openLinkState == DmLinkState.waiting) {
      slot = ComposerNotice(
        icon: Icons.hourglass_empty_rounded,
        text:
            'Your message request is waiting. You can send more once $name '
            'accepts it.',
      );
    } else if (state.openLinkState == DmLinkState.none &&
        state.openPeerPolicy == DmPolicy.nobody) {
      slot = ComposerNotice(
        icon: Icons.do_not_disturb_on_outlined,
        text:
            '$name only takes messages from people they already talk to on '
            'this server.',
      );
    } else if (state.openLinkState == DmLinkState.none &&
        state.openPeerPolicy == DmPolicy.requests) {
      // Said before sending, not after: the first message is all they get
      // until the other side answers, so it is worth knowing while writing it.
      slot = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: Text(
              '$name asks first. Your first message goes as a request, and '
              'you can send more once they accept.',
              style: AppText.meta.copyWith(color: context.theme.textTertiary),
            ),
          ),
          composer,
        ],
      );
    } else if (state.openLinkState.isRequestToMe) {
      slot = Column(
        mainAxisSize: MainAxisSize.min,
        // The width of the composer under it, like every notice in this slot.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DmRequestBanner(
            peerId: peerId,
            peerName: name,
            ignored: state.openLinkState == DmLinkState.ignored,
          ),
          composer,
        ],
      );
    } else {
      slot = composer;
    }
    return TimeOutGate(until: until, child: slot);
  }
}
