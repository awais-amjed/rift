import 'package:flutter/material.dart';

import '../../../../../../../../data/constants.dart';
import '../../../../../../../theme/app_text.dart';
import '../../../../../../../theme/custom_colors.dart';
import '../../../../../../../theme/theme_context.dart';

/// Says a bot can hear this call.
///
/// The voice half of BOTS.md §6's fourth rule. A bot in a call is normally
/// deaf — its token is minted without `canSubscribe` (`009_bot_voice.sql`) — so this
/// only ever appears where an admin has decided otherwise, and the people
/// bearing that decision are not the ones who made it.
///
/// Amber, like the header chip that says a bot is reading a text channel, and
/// for the same reason: it is the same fact wearing a different hat. Somebody
/// other than the room can hear what is said in it.
///
/// Sits on the tile at every size, including the plain row an empty channel
/// gets — an empty voice channel is exactly the one nobody is looking at, and
/// a marker that appears only once a call starts is one you notice after
/// speaking rather than before.
class VoiceListeningBadge extends StatelessWidget {
  /// Display names of the bots that can hear this channel.
  final List<String> listeners;

  const VoiceListeningBadge({super.key, required this.listeners});

  String get _tooltip {
    final names = listeners.join(', ');
    return listeners.length == 1
        ? '$names can hear this channel. A server admin allowed it, and '
              'everyone who speaks here is heard by it.'
        : 'These bots can hear this channel: $names. A server admin allowed '
              'them, and everyone who speaks here is heard by them.';
  }

  @override
  Widget build(BuildContext context) {
    if (listeners.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: _tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: CustomColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(K.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Icon(
              Icons.hearing_rounded,
              size: K.iconTiny,
              color: context.theme.statusInk(CustomColors.warning),
            ),
            Text(
              // The count, not the name: a sidebar row is already carrying a
              // channel name and a roster, and the names are one hover away in
              // the tooltip.
              listeners.length == 1 ? 'HEARD' : '${listeners.length} HEARING',
              style: AppText.sectionLabel.copyWith(
                letterSpacing: 0.6,
                color: context.theme.statusInk(CustomColors.warning),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
