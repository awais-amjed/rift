import 'package:flutter/material.dart';

import '../../../../common/empty_state.dart';
import '../../../../theme/theme_context.dart';

/// The voice stage while the LiveKit connection is being made.
class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      color: themeState.bgSecondary,
      child: const EmptyState(
        icon: Icons.sync_rounded,
        busy: true,
        title: 'Connecting…',
        message: 'Joining the voice channel.',
      ),
    );
  }
}
