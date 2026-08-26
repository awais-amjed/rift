import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/status_chip.dart';
import '../../../../theme/custom_colors.dart';

/// Says a bot is reading this channel.
///
/// Every other bot grant is small enough to be a checkbox. This one hands out
/// the plaintext of a room, and the person who clicked the button is not the
/// person whose messages are being read — so a warning in the admin's dialog
/// reaches the wrong audience entirely (BOTS.md §6, rule 4).
///
/// A standing marker in the header, then, next to the "Encrypted" chip and
/// deliberately in tension with it: like the light on a recorder, on for as
/// long as it is true and impossible to dismiss. It is not behind a menu,
/// because a notice you have to go looking for only tells the people who
/// already knew.
class ChannelListenersChip extends StatelessWidget {
  /// Display names of the bots holding a key to this channel.
  final List<String> listeners;

  const ChannelListenersChip({super.key, required this.listeners});

  String get _label => listeners.length == 1
      ? '${listeners.first} is reading'
      : '${listeners.length} bots reading';

  /// Names them, because "a bot is reading this" is only half the sentence and
  /// *which* bot is the half somebody can act on.
  String get _tooltip {
    final names = listeners.join(', ');
    return listeners.length == 1
        ? '$names holds this channel’s encryption key and can read every '
              'message sent here from now on. A server admin granted it.'
        : 'These bots hold this channel’s encryption key and can read '
              'every message sent here from now on: $names. '
              'A server admin granted them.';
  }

  @override
  Widget build(BuildContext context) {
    if (listeners.isEmpty) return const SizedBox.shrink();
    // Read for the theme so the chip participates in palette changes like
    // everything else in the header.
    context.watch<ThemeCubit>();
    return StatusChip(
      icon: Icons.hearing_rounded,
      label: _label,
      // Amber, matching the unencrypted badge: this is the same fact wearing a
      // different hat — somebody other than the room can read what is said.
      color: CustomColors.warning,
      tooltip: _tooltip,
    );
  }
}
