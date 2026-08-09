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
    description: 'Create channels and moderate members',
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
