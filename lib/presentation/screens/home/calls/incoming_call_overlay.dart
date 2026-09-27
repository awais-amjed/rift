import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/dm_call/dm_call_cubit.dart';
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
class IncomingCallOverlay extends StatelessWidget {
  final Widget child;

  const IncomingCallOverlay({super.key, required this.child});

  Future<void> _answer(BuildContext context, IncomingDmCall incoming) async {
    final calls = context.read<DmCallCubit>();
    // On a phone the call is a page, and it opens by itself when the room
    // does. On a desktop the call is drawn in its conversation, so that is
    // what is put on screen.
    final phone = context.layoutMode.isCompact;
    final joined = await calls.answer(incoming);
    if (!joined || phone || !context.mounted) return;
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
    return Stack(
      children: [
        child,
        Positioned(
          top: 12,
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
