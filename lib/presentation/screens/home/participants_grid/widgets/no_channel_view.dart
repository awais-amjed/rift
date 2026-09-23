import 'package:flutter/material.dart';

import '../../../../common/empty_state.dart';
import '../../../../theme/theme_context.dart';

/// What fills the content pane when no text channel is open.
///
/// Two states arrive here and they are not the same thing, which is why there
/// are two constructors rather than one message. Nothing selected at all is
/// the *app's* empty state — the first thing a new member sees on a server
/// they have just joined — and it used to read "Pick a voice channel from the
/// sidebar to join", because this widget belongs to the voice stage and was
/// answering for it. The one thing a new member is about to do is open
/// #general.
class NoChannelView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// Nothing is selected. Names both kinds of channel, text first.
  const NoChannelView.nothingSelected({super.key})
    : icon = Icons.forum_outlined,
      title = 'No channel selected',
      message =
          'Pick a channel from the sidebar. Text channels open here, '
          'voice channels put you in a call.';

  /// A voice channel is selected and this device is not in the call — after
  /// hanging up, or before joining one.
  const NoChannelView.notInCall({super.key})
    : icon = Icons.mic_none_rounded,
      title = 'Not in a call',
      message = 'Join a voice channel from the sidebar to start talking.';

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      color: themeState.bgSecondary,
      child: EmptyState(icon: icon, title: title, message: message),
    );
  }
}
