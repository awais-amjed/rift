import 'package:flutter/material.dart';

import '../../../../common/empty_state.dart';

/// The voice stage while nobody else has arrived.
class WaitingView extends StatelessWidget {
  const WaitingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.people_outline,
      title: 'Waiting for others',
      message: "You're the first one here.",
    );
  }
}
