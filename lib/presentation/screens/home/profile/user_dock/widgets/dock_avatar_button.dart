import 'package:flutter/material.dart';

import '../../../../../../data/classes/server_user.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/user_avatar.dart';
import '../../../../../theme/app_motion.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// Your avatar in the dock, and the way into the profile editor.
///
/// It has no way of saying it is a control: a picture of a person is a picture
/// of a person, and an ink highlight can't help here the way it can elsewhere
/// — the avatar it would sit behind is opaque, so the ripple is drawn and then
/// painted over. It lifts itself instead, and says what the click does while
/// it's at it: the picture dims under the pointer and a pencil comes up over
/// it. A highlight would only have raised the question this answers.
class DockAvatarButton extends StatefulWidget {
  final ServerUser? user;
  final VoidCallback onTap;

  const DockAvatarButton({super.key, required this.user, required this.onTap});

  @override
  State<DockAvatarButton> createState() => _DockAvatarButtonState();
}

class _DockAvatarButtonState extends State<DockAvatarButton> {
  static const double _size = 34;

  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // The avatar's own corner, from the same ratio it uses, rather than a
    // literal that drifts the first time an avatar changes size.
    final radius = BorderRadius.circular(_size * K.avatarRadiusRatio);

    return Tooltip(
      message: 'Edit profile',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovering = value),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(
                avatarPath: widget.user?.avatarPath,
                name: widget.user?.displayName ?? 'Guest',
                size: _size,
              ),
              Positioned.fill(child: _overlay(themeState, radius)),
              Positioned(right: -2, bottom: -2, child: _statusDot(themeState)),
            ],
          ),
        ),
      ),
    );
  }

  /// Dims the picture rather than tinting it: an avatar can be a dark gradient
  /// or a bright photograph, and only darkening reads the same on both.
  Widget _overlay(ThemeState themeState, BorderRadius radius) {
    return AnimatedOpacity(
      opacity: _hovering ? 1 : 0,
      duration: AppMotion.react,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: themeState.bgPrimary.withValues(alpha: 0.62),
          borderRadius: radius,
        ),
        child: Center(
          child: Icon(
            Icons.edit_rounded,
            size: 14,
            color: themeState.textPrimary,
          ),
        ),
      ),
    );
  }

  /// Ringed in the panel colour, not the dock's, so the dot reads as punched
  /// through the avatar rather than stuck on it.
  Widget _statusDot(ThemeState themeState) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: widget.user != null
            ? CustomColors.userStatusOnline
            : themeState.textQuaternary,
        shape: BoxShape.circle,
        border: Border.all(color: themeState.bgSecondary, width: 2.5),
      ),
    );
  }
}
