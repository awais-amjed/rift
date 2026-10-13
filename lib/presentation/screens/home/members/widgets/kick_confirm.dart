import 'package:flutter/material.dart';

import '../../../../common/confirm_dialog.dart';

/// Asks before a kick, from wherever one is offered.
///
/// It asks, like a ban, because it cuts somebody off mid-sentence and takes
/// their roles with it — and unlike a ban it says how they get back, so the
/// moderator choosing between the two can see the difference. A bot loses
/// more (what it could read and hear), and only a bot invite brings it back.
Future<bool> confirmKick(
  BuildContext context,
  String name, {
  bool isBot = false,
}) => showConfirmDialog(
  context: context,
  title: 'Kick $name?',
  message: isBot
      ? 'It is removed from this server now, and loses its roles, the '
            'channels it could read and the calls it could hear. Its '
            'messages stay. A new bot invite brings it back.'
      : 'They are removed from this server now, and lose their roles and '
            'private channels. Their messages stay. A new invite brings '
            'them back as themselves.',
  confirmLabel: 'Kick',
  icon: Icons.logout_rounded,
  isDestructive: true,
);
