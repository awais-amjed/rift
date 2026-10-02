import 'package:flutter/material.dart';

import '../../../../common/confirm_dialog.dart';

/// Asks before a kick, from wherever one is offered.
///
/// It asks, like a ban, because it cuts somebody off mid-sentence and takes
/// their roles with it — and unlike a ban it says how they get back, so the
/// moderator choosing between the two can see the difference.
Future<bool> confirmKick(BuildContext context, String name) =>
    showConfirmDialog(
      context: context,
      title: 'Kick $name?',
      message:
          'They are removed from this server now, and lose their roles and '
          'private channels. Their messages stay. A new invite brings them '
          'back as themselves.',
      confirmLabel: 'Kick',
      icon: Icons.logout_rounded,
      isDestructive: true,
    );
