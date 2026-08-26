import 'package:flutter/material.dart';

import '../../data/classes/user_permissions.dart';

/// The three things a member can be granted, described once.
///
/// Two surfaces hand these out — the Members dialog and the participant
/// context menu — and they have to agree on what each one is called and what it
/// means. Wording that drifts between the two reads as two different
/// permissions rather than one shown twice.
///
/// The setter is deliberately *not* here: `set_user_permissions` takes three
/// named booleans, so each call site switches on the role to pick one and the
/// compiler checks it. Only the description is shared, because only the
/// description can silently disagree.
enum ServerRole {
  admin(
    label: 'Server Admin',
    description: 'Full server management access',
    icon: Icons.shield_outlined,
  ),
  channelManager(
    label: 'Channel Manager',
    // Checked against `moderate_user`, which splits on the verb rather than
    // the role: banning takes `app.is_admin()`, everything else takes
    // `app.can_manage_channels()`. So mute and deafen ARE a manager's, and ban
    // is the one thing that is not. Naming the exclusion matters more than
    // listing the grants — it is the half people get wrong.
    description:
        'Manage channels, remove any message, and mute, deafen or '
        'disconnect members — but not ban',
    icon: Icons.tune_outlined,
  ),
  invites(
    label: 'Can Invite',
    description: 'Allowed to generate invite codes',
    icon: Icons.link_outlined,
  );

  const ServerRole({
    required this.label,
    required this.description,
    required this.icon,
  });

  final String label;
  final String description;
  final IconData icon;

  bool isHeldBy(UserPermissions permissions) => switch (this) {
    ServerRole.admin => permissions.isServerAdmin,
    ServerRole.channelManager => permissions.isChannelManager,
    ServerRole.invites => permissions.canCreateTokens,
  };
}
