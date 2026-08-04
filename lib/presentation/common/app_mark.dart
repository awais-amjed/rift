import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_shadows.dart';

/// Rift's brand mark: a squircle of the palette's identity gradient.
///
/// Deliberately wordless and palette-driven — it is the same shape as a server
/// chip or an avatar, so the app's own identity sits in the same visual family
/// as everyone else's.
class AppMark extends StatelessWidget {
  final double size;

  /// Knocked out of the gradient in white. Only the large hero mark carries
  /// one — at title-bar size a glyph would be mud.
  final IconData? icon;

  /// Casts the accent glow under the mark. For the hero mark, which has to
  /// hold the middle of an otherwise empty canvas.
  final bool glow;

  const AppMark({super.key, this.size = 16, this.icon, this.glow = false});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: themeState.identityGradient,
            borderRadius: BorderRadius.circular(size * K.avatarRadiusRatio),
            boxShadow: glow
                ? AppShadows.accentGlow(
                    themeState.primary,
                    blurRadius: 40,
                    dy: 10,
                  )
                : null,
          ),
          child: icon == null
              ? null
              : Icon(icon, size: size / 2, color: Colors.white),
        );
      },
    );
  }
}
