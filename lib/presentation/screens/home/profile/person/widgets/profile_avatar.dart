import 'package:flutter/material.dart';

import '../../../../../common/user_avatar.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// The person's picture at the head of their profile, with a presence dot
/// when the surface knows about presence.
///
/// [isOnline] is nullable rather than defaulting to false: a central account
/// has no presence at all, and a grey dot there would be a claim that they
/// are offline rather than an admission that nobody is watching.
class ProfileAvatar extends StatelessWidget {
  static const double _size = 44;
  static const double _dot = 12;

  final String name;
  final String? avatarPath;

  /// A user id, so the fallback gradient survives a rename.
  final String? seed;

  final bool? isOnline;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.avatarPath,
    this.seed,
    this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final online = isOnline;
    final avatar = UserAvatar(
      avatarPath: avatarPath,
      name: name,
      seed: seed,
      size: _size,
    );
    if (online == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: _dot,
            height: _dot,
            decoration: BoxDecoration(
              color: online
                  ? CustomColors.userStatusOnline
                  : context.theme.textQuaternary,
              shape: BoxShape.circle,
              // Ringed in the dialog's own surface, so it reads as a cut-out
              // of the avatar rather than a badge sitting on it.
              border: Border.all(color: context.theme.bgSecondary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
