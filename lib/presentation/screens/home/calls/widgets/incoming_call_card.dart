import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../common/calls/call_action_button.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One call ringing this device: who, from which server, and the two
/// answers. The picture is drawn from initials, not fetched: the call may be
/// on a server other than the one selected, whose storage this device is not
/// signed in to at the moment it rings.
class IncomingCallCard extends StatelessWidget {
  final IncomingDmCall incoming;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const IncomingCallCard({
    super.key,
    required this.incoming,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final busy = context.select<DmCallCubit, bool>((c) => c.state.busy);
    final call = incoming.call;
    return Container(
      constraints: const BoxConstraints(maxWidth: K.incomingCallWidth),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: theme.bgElevated,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderElevated),
        boxShadow: AppShadows.popover,
      ),
      child: Row(
        spacing: 12,
        children: [
          SquircleAvatar(
            name: call.peerName,
            seed: call.peerId,
            size: K.incomingCallAvatar,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  call.peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.strong.copyWith(color: theme.textPrimary),
                ),
                Text(
                  'Calling you · ${incoming.serverName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.secondary.copyWith(color: theme.textTertiary),
                ),
              ],
            ),
          ),
          CallActionButton.end(
            tooltip: 'Decline',
            onTap: busy ? null : onDecline,
          ),
          CallActionButton.accept(onTap: busy ? null : onAnswer),
        ],
      ),
    );
  }
}
