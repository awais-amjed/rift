import 'package:material_ui/material_ui.dart';

import '../../confirm_dialog.dart';

/// Ask before ending a poll early: it cannot be taken back, and it ends it
/// for everyone. Every place that offers "End poll" asks this — the live bar
/// once ended one at a press (review, Nov 22).
Future<bool> confirmEndPoll(BuildContext context) => showConfirmDialog(
  context: context,
  title: 'End this poll?',
  message: 'Voting stops now for everyone, and the results are final.',
  confirmLabel: 'End poll',
  icon: Icons.poll_outlined,
);
