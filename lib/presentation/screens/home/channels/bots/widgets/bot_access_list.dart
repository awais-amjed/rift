import 'package:flutter/material.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../theme/app_text.dart';
import 'bot_channel_row.dart';
import '../../../../../theme/theme_context.dart';

/// One labelled list of channels a bot can reach.
///
/// Both halves of [BotAccessDialog] are this shape — a heading, the channels,
/// and a sentence for the far commoner case of none — and the empty sentence is
/// the reason it is worth sharing rather than writing twice. "It reads nothing"
/// and "it hears nothing" are the two facts most likely to surprise somebody
/// arriving from Discord, and they should be impossible to add to one list and
/// forget in the other.
class BotAccessList extends StatelessWidget {
  final String label;
  final List<Channel> channels;
  final IconData emptyIcon;
  final String emptyText;

  /// Sits between the label and the list. Only the reading half has one — the
  /// server-wide toggle, which belongs to that grant and has no voice
  /// equivalent by design (BOTS.md §6: there is no bulk form for hearing).
  final Widget? control;

  const BotAccessList({
    super.key,
    required this.label,
    required this.channels,
    required this.emptyIcon,
    required this.emptyText,
    this.control,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: AppText.sectionLabel.copyWith(
              color: themeState.textTertiary,
            ),
          ),
        ),
        if (control != null) ...[control!, const SizedBox(height: 16)],
        if (channels.isEmpty)
          HintCard(icon: emptyIcon, text: emptyText)
        else
          for (final channel in channels) BotChannelRow(channel: channel),
      ],
    );
  }
}
