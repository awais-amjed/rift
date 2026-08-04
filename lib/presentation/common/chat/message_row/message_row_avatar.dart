import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../user_avatar.dart';

/// The author's picture in a header row's gutter, falling back to an initial.
class MessageRowAvatar extends StatelessWidget {
  static const double size = 34;

  final String authorName;
  final String? avatarPath;
  final ThemeState themeState;

  /// The author's user id, so their colour survives a display-name change.
  final String? authorId;

  const MessageRowAvatar({
    super.key,
    required this.authorName,
    required this.themeState,
    this.avatarPath,
    this.authorId,
  });

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      avatarPath: avatarPath,
      name: authorName,
      seed: authorId,
      size: size,
      themeState: themeState,
    );
  }
}
