import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import '../../../data/repositories/session_repository.dart';
import '../../../logic/services/notification_service.dart';
import '../../common/server_scope.dart';
import '../../theme/app_motion.dart';
import 'in_app_message_banner.dart';

/// Shows a mention or a DM that arrived while the window is focused, as an
/// [InAppMessageBanner] that opens it when pressed
/// (`NotificationService.showInApp`).
///
/// The system's notification is kept for a window out of sight; over the one
/// being used it is noise. But the chime alone said only that something
/// arrived, and the person had to hunt the badges for where. The press goes
/// where a notification's does (`ConversationNotificationRouter`), so it opens
/// the same way.
///
/// It holds the time each banner stays up itself, rather than handing it to
/// toastification, because that timer cannot start over: the same thing said
/// again keeps the banner up instead of stacking a copy, so somebody sending
/// ten lines in a row is one banner.
class InAppMessageToasts extends StatefulWidget {
  final Widget child;

  const InAppMessageToasts({super.key, required this.child});

  /// Long enough to read a name and a channel and reach for it.
  static const Duration showFor = Duration(seconds: 5);

  /// The most on screen at once. Older ones go: their badges are still there.
  static const int mostAtOnce = 3;

  @override
  State<InAppMessageToasts> createState() => _InAppMessageToastsState();
}

class _InAppMessageToastsState extends State<InAppMessageToasts> {
  StreamSubscription<InAppMessage>? _messages;

  /// What is up, oldest first, under what it says.
  final Map<String, _Shown> _shown = {};

  @override
  void initState() {
    super.initState();
    _messages = NotificationService.instance.inAppMessages.listen(_show);
  }

  @override
  void dispose() {
    unawaited(_messages?.cancel());
    for (final key in _shown.keys.toList()) {
      _close(key);
    }
    super.dispose();
  }

  void _show(InAppMessage message) {
    final key = '${message.target.encode()}|${message.sender}|${message.what}';
    final showing = _shown[key];
    if (showing != null) {
      if (!showing.hovered) _startClock(key);
      return;
    }
    if (_shown.length >= InAppMessageToasts.mostAtOnce) {
      _close(_shown.keys.first);
    }
    final server = message.target.serverId.isEmpty
        ? null
        : context.read<SessionRepository>().on(message.target.serverId);
    final item = toastification.showCustom(
      alignment: Alignment.topCenter,
      animationDuration: AppMotion.enter,
      animationBuilder: _slideDown,
      builder: (context, _) {
        final banner = InAppMessageBanner(
          senderId: message.senderId,
          sender: message.sender,
          avatarPath: message.avatarPath,
          what: message.what,
          place: message.place,
          isMention: message.target.isChannel,
          onClose: () => _close(key),
          onHover: (over) => _hold(key, over),
          onTap: () {
            _close(key);
            NotificationService.instance.pressInApp(message.target);
          },
        );
        // The picture is on the server the message is, whichever is selected.
        return server == null
            ? banner
            : ServerScope(server: server, child: banner);
      },
    );
    _shown[key] = _Shown(item);
    _startClock(key);
  }

  void _startClock(String key) {
    final showing = _shown[key];
    if (showing == null) return;
    showing.clock?.cancel();
    showing.clock = Timer(InAppMessageToasts.showFor, () => _close(key));
  }

  /// Held while the mouse is on it: it is being read, or about to be pressed.
  void _hold(String key, bool over) {
    final showing = _shown[key];
    if (showing == null) return;
    showing.hovered = over;
    if (over) {
      showing.clock?.cancel();
    } else {
      _startClock(key);
    }
  }

  void _close(String key) {
    final showing = _shown.remove(key);
    if (showing == null) return;
    showing.clock?.cancel();
    toastification.dismiss(showing.item);
  }

  static Widget _slideDown(
    BuildContext context,
    Animation<double> animation,
    Alignment alignment,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.arrive);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -0.6),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Shown {
  final ToastificationItem item;
  Timer? clock;
  bool hovered = false;

  _Shown(this.item);
}
