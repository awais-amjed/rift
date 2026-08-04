import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';

/// Rift's brand mark: a squircle of the palette's identity gradient.
///
/// Deliberately wordless and palette-driven — it is the same shape as a server
/// chip or an avatar, so the app's own identity sits in the same visual family
/// as everyone else's.
class AppMark extends StatelessWidget {
  final double size;

  const AppMark({super.key, this.size = 16});

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
          ),
        );
      },
    );
  }
}
