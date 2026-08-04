import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';

/// One of the app's floating panels — sidebar, content, members.
///
/// The redesign has no full-bleed surfaces: every region is a rounded,
/// bordered panel sitting on the canvas with a gutter around it. That chrome
/// lives here so the panels can't drift apart from each other.
///
/// Content panels (chat, voice stage, settings body) pass
/// `color: theme.bgContent`; chrome panels take the default.
class AppPanel extends StatelessWidget {
  final Widget child;

  /// Panel background. Defaults to the chrome surface (`bgSecondary`).
  final Color? color;

  /// Fixed width, for panels that don't flex (sidebar, members).
  final double? width;

  /// Cast when the panel floats over other panels rather than sitting beside
  /// them — the unpinned sidebar sliding out over the chat.
  final List<BoxShadow>? shadow;

  const AppPanel({
    super.key,
    required this.child,
    this.color,
    this.width,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          width: width,
          decoration: BoxDecoration(
            color: color ?? themeState.bgSecondary,
            borderRadius: BorderRadius.circular(K.radiusPanel),
            border: Border.all(color: themeState.borderPrimary),
            boxShadow: shadow,
          ),
          // The border is painted inside the box, so the clip has to shrink by
          // its width or children bleed over it at the corners.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(K.radiusPanel - 1),
            child: child,
          ),
        );
      },
    );
  }
}
