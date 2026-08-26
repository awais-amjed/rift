import 'package:flutter/material.dart';

/// One thing you can do to a person from a row in the friends list.
///
/// A value rather than a widget so that the row stays a row: which actions
/// exist depends entirely on where you stand with someone — accept and decline
/// for a request, unfriend and block for a friend, unblock for a block — and
/// the row should not be a switch over [FriendshipState] with five branches of
/// buttons inside it.
class FriendRowAction {
  final IconData icon;

  /// What the button says on hover. There is no room for labels on the row,
  /// so this is the only place the action is named — it is not optional.
  final String tooltip;

  final VoidCallback onTap;

  /// Draws in the error colour. For the ones that end something: decline,
  /// unfriend, block.
  final bool isDangerous;

  const FriendRowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isDangerous = false,
  });
}
