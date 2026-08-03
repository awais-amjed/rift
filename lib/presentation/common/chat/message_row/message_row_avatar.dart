import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../user_avatar.dart';

/// The author's picture in a header row's gutter, falling back to an initial.
class MessageRowAvatar extends StatelessWidget {
  static const double size = 34;

  final String authorName;
  final String? avatarPath;
  final ThemeState themeState;

  const MessageRowAvatar({
    super.key,
    required this.authorName,
    required this.themeState,
    this.avatarPath,
  });

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      avatarPath: avatarPath,
      name: authorName,
      size: size,
      themeState: themeState,
    );
  }
}
