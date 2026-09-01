import 'package:flutter/material.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';

/// One channel on the list of what a bot can reach.
///
/// Shared by the two lists in [BotAccessDialog] — what it reads and what it
/// hears — which is why the lock lives here: a private channel is worth
/// pointing out in both, and it was the sort of detail that gets added to one
/// list and forgotten in the other.
class BotChannelRow extends StatelessWidget {
  final ThemeState themeState;
  final Channel channel;

  const BotChannelRow({
    super.key,
    required this.themeState,
    required this.channel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            channel.channelType == ChannelType.voice
                ? Icons.volume_up_rounded
                : Icons.tag_rounded,
            size: 15,
            color: themeState.textTertiary,
          ),
          Expanded(
            child: Text(
              channel.name,
              style: AppText.row.copyWith(color: themeState.textPrimary),
            ),
          ),
          if (channel.isPrivate)
            Icon(Icons.lock_rounded, size: 13, color: themeState.textTertiary),
        ],
      ),
    );
  }
}
