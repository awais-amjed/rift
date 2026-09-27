import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import 'open_call_conversation.dart';
import 'widgets/incoming_call_card.dart';

/// A call ringing this device, over whatever is on screen.
///
/// At the top of the window rather than in a dialog, because a dialog would
/// take the keyboard and the pointer from whatever you were doing — and a
/// call you mean to ignore should be ignorable. The newest ring is the one
/// shown; a second caller waits under it until the first is answered or goes.
///
/// Mounted around the app's navigator (`MaterialApp.builder`), not inside the
/// home screen: a card drawn inside a page sits *under* every dialog and
/// sheet opened on top of it, and a call rang unseen behind the server
/// switcher while it was open. Up here there is no overlay or material to
/// borrow, so it brings its own.
///
/// The overlay's one entry is made once and draws [_RingingCard], which
/// watches the calls itself. An `Overlay` reads its entries on its first
/// build and never again, so a card built out here and handed in would be
/// frozen at whatever was ringing when the app started — nothing, and the
/// first version of this showed no call at all.
class IncomingCallOverlay extends StatefulWidget {
  final Widget child;

  const IncomingCallOverlay({super.key, required this.child});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) =>
        const Material(type: MaterialType.transparency, child: _RingingCard()),
  );

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      // Its own overlay, for the buttons' tooltips; its own material, for
      // their ink and the card's text.
      Positioned.fill(child: Overlay(initialEntries: [_entry])),
    ],
  );
}

/// The newest ring, at the top of the window, or nothing.
class _RingingCard extends StatelessWidget {
  const _RingingCard();

  Future<void> _answer(BuildContext context, IncomingDmCall incoming) async {
    final calls = context.read<DmCallCubit>();
    // On a phone the call is a page, and it opens by itself when the room
    // does. On a desktop the call is drawn in its conversation, so that is
    // what is put on screen.
    final phone = context.layoutMode.isCompact;
    final joined = await calls.answer(incoming);
    if (!joined) return;
    clearPopupsForCall();
    if (phone || !context.mounted) return;
    await openCallConversation(
      context,
      serverId: incoming.serverId,
      call: incoming.call,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ringing = context.select<DmCallCubit, IncomingDmCall?>(
      (c) => c.state.incoming.firstOrNull,
    );
    // Clear of the title bar a desktop window draws over its own top edge.
    final top = HostPlatform.drawsOwnWindowChrome
        ? K.titleBarHeight + 12
        : 12.0;
    return Stack(
      children: [
        Positioned(
          top: top,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: AppMotion.enter,
                switchInCurve: AppMotion.arrive,
                switchOutCurve: AppMotion.settle,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, -0.3),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: ringing == null
                    ? const SizedBox.shrink()
                    : IncomingCallCard(
                        key: ValueKey(ringing.call.id),
                        incoming: ringing,
                        onAnswer: () => unawaited(_answer(context, ringing)),
                        onDecline: () => unawaited(
                          context.read<DmCallCubit>().decline(ringing),
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
