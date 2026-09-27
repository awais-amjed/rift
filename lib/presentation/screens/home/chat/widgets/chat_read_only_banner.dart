import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../common/chat/composer_notice.dart';

/// Sits under a channel this member can see but not fully read, in place of the
/// composer.
///
/// It has to answer two questions the message list cannot. **Why are some of
/// these locked** — nobody has wrapped the channel key for this device yet — and
/// **why can I not type** — because sending needs that same key, so there is no
/// half-open state to offer.
///
/// Taking the composer's slot rather than sitting above the list is the point:
/// the thing it explains is the thing that is missing, and an explanation
/// somewhere else would leave a hole with no caption.
///
/// [waitingForKey] is the same slot before any history can be shown at all.
/// It has nothing to retry — the key arrives on its own, and the page above
/// says who it is waiting on — so it only promises that this will work.
class ChatReadOnlyBanner extends StatelessWidget {
  final bool waitingForKey;

  const ChatReadOnlyBanner({super.key, this.waitingForKey = false});

  @override
  Widget build(BuildContext context) {
    return ComposerNotice(
      icon: Icons.lock_outline_rounded,
      text: waitingForKey
          ? 'You can read and send here once the key arrives'
          : 'You cannot read or send here yet — another member needs '
                'to come online to grant you this channel’s key.',
      actionLabel: waitingForKey ? null : 'Try again',
      onAction: waitingForKey
          ? null
          : () => context.read<ChannelChatCubit>().retry(),
    );
  }
}
