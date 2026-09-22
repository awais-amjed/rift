import 'package:flutter/material.dart';

import '../../member_avatar.dart';
import '../../user_avatar.dart';

/// The author's picture in a header row's gutter, falling back to an initial.
///
/// The roster's copy wins over [avatarPath], which is the picture as it was
/// when the message loaded: a member changing theirs left every message
/// already on screen showing the old one.
class MessageRowAvatar extends StatelessWidget {
  static const double size = 34;

  final String authorName;
  final String? avatarPath;

  /// The author's user id, so their colour survives a display-name change.
  final String? authorId;

  const MessageRowAvatar({
    super.key,
    required this.authorName,
    this.avatarPath,
    this.authorId,
  });

  @override
  Widget build(BuildContext context) {
    final authorId = this.authorId;
    if (authorId != null) {
      return MemberAvatar(
        userId: authorId,
        name: authorName,
        size: size,
        fallbackPath: avatarPath,
      );
    }
    return UserAvatar(
      avatarPath: avatarPath,
      name: authorName,
      seed: authorId,
      size: size,
    );
  }
}
