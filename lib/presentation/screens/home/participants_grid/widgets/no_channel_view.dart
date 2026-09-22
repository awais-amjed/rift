import 'package:flutter/material.dart';

import '../../../../common/empty_state.dart';
import '../../../../theme/theme_context.dart';

/// The voice stage with no channel selected.
class NoChannelView extends StatelessWidget {
  const NoChannelView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      color: themeState.bgSecondary,
      child: EmptyState(
        icon: Icons.mic_none_rounded,
        title: 'No channel selected',
        message: 'Pick a voice channel from the sidebar to join.',
      ),
    );
  }
}
