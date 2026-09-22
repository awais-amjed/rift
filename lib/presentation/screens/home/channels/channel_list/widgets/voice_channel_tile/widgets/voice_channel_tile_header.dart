import 'package:flutter/material.dart';

import '../../../../../../../../data/classes/channel.dart';
import '../../../../../../../../data/constants.dart';
import '../../../../../../../theme/app_text.dart';
import '../../../../../../../theme/theme_context.dart';
import '../../channel_lock_badge.dart';
import 'live_badge.dart';
import 'roster_row_metrics.dart';
import 'voice_listening_badge.dart';

/// The clickable row at the top of an occupied voice channel's card: the
/// channel's name, its lock, whether a bot can hear it, and the LIVE tag.
///
/// Its own widget because the card around it is a container and a roster, and
/// this is the only part of it you can press — keeping them apart is what stops
/// the tile growing a third job every time voice gains a badge.
class VoiceChannelTileHeader extends StatelessWidget {
  final Channel channel;
  final bool isSelected;

  /// Display names of the bots that can hear this channel. Empty is the common
  /// case and draws nothing.
  final List<String> listeners;

  final VoidCallback? onTap;

  const VoiceChannelTileHeader({
    super.key,
    required this.channel,
    required this.isSelected,
    required this.listeners,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // The tile paints its own card, so the ink needs a surface inside it —
    // otherwise the highlight lands on the sidebar behind and the card covers
    // it, and the one row you can click looks exactly like the roster rows
    // under it, which you cannot.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(K.radiusRow),
        onTap: onTap,
        child: Padding(
          // The people rows' horizontal padding, so the speaker icon lines
          // up with the avatars under it and the two hovers are one width.
          padding: EdgeInsets.symmetric(
            horizontal: RosterRowMetrics.of(context).padding.left,
            vertical: RosterRowMetrics.of(context).headerVerticalPadding,
          ),
          child: Row(
            spacing: 9,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      size: 16,
                      color: isSelected
                          ? themeState.accentBright
                          : themeState.textTertiary,
                    ),
                    if (channel.isPrivate)
                      const Positioned(
                        right: -4,
                        bottom: -3,
                        child: ChannelLockBadge(),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(
                    color: isSelected
                        ? themeState.channelActiveText
                        : themeState.textSecondary,
                  ),
                ),
              ),
              // Before LIVE, not after: whether you can be heard by a bot is
              // the thing to read before deciding to speak, and LIVE is about
              // the call you already joined.
              VoiceListeningBadge(listeners: listeners),
              if (isSelected) const LiveBadge(),
            ],
          ),
        ),
      ),
    );
  }
}
