import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_call_place.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../common/calls/call_action_button.dart';
import '../../../../common/centered_scroll_view.dart';
import '../../../../common/loading_dots.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Our own DM call while it rings at the other end: who, that it is
/// ringing, and the way to stop. The room is already up behind it, so the
/// moment they pick up this gives way to the call itself.
class DmRingingView extends StatelessWidget {
  final DmCallPlace place;

  const DmRingingView({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final avatarPath = context.select<DmCallCubit, String?>(
      (c) => c.state.active?.call.peerAvatarPath,
    );
    return CenteredScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            name: place.peerName,
            seed: place.peerId,
            avatarPath: avatarPath,
            size: K.callAvatar,
          ),
          const SizedBox(height: 16),
          Text(
            place.peerName,
            textAlign: TextAlign.center,
            style: AppText.sectionTitle.copyWith(color: theme.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text(
                'Ringing',
                style: AppText.secondary.copyWith(color: theme.textTertiary),
              ),
              LoadingDots(color: theme.textTertiary, dotSize: 4),
            ],
          ),
          const SizedBox(height: 28),
          CallActionButton.end(
            tooltip: 'Cancel call',
            onTap: () => context.read<DmCallCubit>().hangUp(),
          ),
        ],
      ),
    );
  }
}
