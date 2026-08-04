import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';

/// The near-black ground the floating panels sit on, lit by a single accent
/// glow from off the top-left corner.
///
/// The glow is what keeps a near-black canvas from reading as dead space, and
/// it takes the palette's accent — so Ember warms the corner and Mono leaves
/// it neutral, without any per-palette special-casing.
class CanvasBackdrop extends StatelessWidget {
  final Widget child;

  const CanvasBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return DecoratedBox(
          decoration: BoxDecoration(color: themeState.bgPrimary),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                // Centred off-canvas above the left third, so the light falls
                // across the sidebar and fades before the chat panel.
                center: const Alignment(-0.4, -1.1),
                radius: 1.1,
                colors: [
                  themeState.primary.withValues(alpha: 0.09),
                  themeState.primary.withValues(alpha: 0),
                ],
                stops: const [0, 0.6],
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
