import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../logic/services/notification_service.dart';
import 'open_call_conversation.dart';

/// Takes presses on a call's notification to the call cubit: the one that
/// launched the app, and any made while it runs.
///
/// Answer answers — the app was opened for exactly that, and on a phone the
/// call page opens by itself when the room does. Decline declines. A press
/// on the notification itself only asks the server, so the ringing card
/// shows up in the app for the person to choose there.
class CallNotificationRouter extends StatefulWidget {
  final Widget child;

  const CallNotificationRouter({super.key, required this.child});

  @override
  State<CallNotificationRouter> createState() => _CallNotificationRouterState();
}

class _CallNotificationRouterState extends State<CallNotificationRouter> {
  StreamSubscription<CallNotificationPress>? _presses;

  @override
  void initState() {
    super.initState();
    _presses = NotificationService.instance.callPresses.listen(_handle);
    unawaited(
      NotificationService.instance.takeLaunchPress().then((press) {
        if (press != null && mounted) _handle(press);
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_presses?.cancel());
    super.dispose();
  }

  void _handle(CallNotificationPress press) {
    final calls = context.read<DmCallCubit>();
    final call = press.call;
    if (press.answers) {
      unawaited(
        calls.answerById(call.serverId, call.callId).then((joined) {
          if (joined) clearPopupsForCall();
        }),
      );
    } else if (press.declines) {
      unawaited(calls.declineById(call.serverId, call.callId));
    } else {
      unawaited(calls.refresh(call.serverId));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
