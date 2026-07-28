import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';

/// The circular initial shown in a header row's gutter.
class MessageRowAvatar extends StatelessWidget {
  static const double size = 34;

  final String authorName;
  final ThemeState themeState;

  const MessageRowAvatar({
    super.key,
    required this.authorName,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: themeState.bgActive,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: themeState.textSecondary,
        ),
      ),
    );
  }
}
