import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../../data/constants.dart';

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
class ChatReadOnlyBanner extends StatelessWidget {
  const ChatReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: themeState.bgTertiary,
          borderRadius: BorderRadius.circular(K.radiusCard),
          border: Border.all(color: themeState.borderElevated),
        ),
        child: Row(
          spacing: 10,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: themeState.textTertiary,
            ),
            Expanded(
              child: Text(
                'You cannot read or send here yet — another member needs to '
                'come online to grant you this channel’s key.',
                style: AppText.meta.copyWith(color: themeState.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => context.read<ChannelChatCubit>().retry(),
              style: TextButton.styleFrom(
                foregroundColor: themeState.primary,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Retry',
                style: AppText.meta.copyWith(
                  fontWeight: FontWeight.w600,
                  color: themeState.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
