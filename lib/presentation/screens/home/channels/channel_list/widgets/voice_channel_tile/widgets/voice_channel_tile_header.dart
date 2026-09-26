import 'package:flutter/material.dart';

import '../../../../../../../../data/classes/channel.dart';
import '../../../../../../../../data/constants.dart';
import '../../../../../../../responsive/shell_scope.dart';
import '../../../../../../../theme/app_motion.dart';
import '../../../../../../../theme/app_text.dart';
import '../../../../../../../theme/theme_context.dart';
import '../../channel_lock_badge.dart';
import 'call_timer.dart';
import 'roster_row_metrics.dart';
import 'voice_listening_badge.dart';

/// The clickable row at the top of a voice channel: the channel's name, its
/// lock, whether a bot can hear it, and how long its call has run.
///
/// The same row whether the channel is empty or holding a call — [card] says
/// how far it is into being the card's header, and the name's weight and the
/// glyph's colour follow it, from a plain sidebar row's to the card's.
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

  /// The settings gear, while the pointer is over the header of a channel the
  /// viewer runs.
  final Widget? gear;

  /// When the call here began, or null with nobody in it.
  final DateTime? startedAt;

  /// 0 for an empty channel's plain row, 1 for an occupied card's header.
  final double card;

  /// Whatever puts the glyph where a sidebar row's is, given how much of the
  /// card's own padding is already to its left.
  final double horizontalPadding;

  const VoiceChannelTileHeader({
    super.key,
    required this.channel,
    required this.isSelected,
    required this.listeners,
    this.onTap,
    this.gear,
    this.startedAt,
    this.card = 1,
    required this.horizontalPadding,
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
        // A rounded row, like the people under it.
        borderRadius: BorderRadius.circular(K.radiusRow),
        onTap: onTap,
        child: Container(
          // One row high, like the plain row an empty channel is drawn as.
          height: RosterRowMetrics.of(context).rowHeight,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                      size: K.iconRow,
                      color: isSelected
                          ? themeState.accentBright
                          : Color.lerp(
                              themeState.textQuaternary,
                              themeState.textTertiary,
                              card,
                            ),
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
                  // A plain row's weight when empty, the card's when not.
                  style: TextStyle.lerp(AppText.rowQuiet, AppText.row, card)!
                      .copyWith(
                        color: isSelected
                            ? themeState.channelActiveText
                            : themeState.textSecondary,
                      ),
                ),
              ),
              // Before the timer, not after: whether you can be heard by a bot
              // is the thing to read before deciding to speak.
              VoiceListeningBadge(listeners: listeners),
              // Fades in and out with the call rather than blinking.
              AnimatedSwitcher(
                duration: AppMotion.enter,
                switchInCurve: AppMotion.settle,
                child: switch (startedAt) {
                  final startedAt? => CallTimer(
                    key: const ValueKey('timer'),
                    startedAt: startedAt,
                    isYours: isSelected,
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
              ?gear,
              // A phone's empty voice row still says a tap opens a page, as
              // every other row there does.
              if (card == 0 && context.layoutMode.isCompact)
                Icon(
                  Icons.chevron_right_rounded,
                  size: K.iconButton,
                  color: themeState.textQuaternary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
