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

  /// Where the light comes from. The app workspace is lit from off the
  /// top-left so the glow falls across the sidebar; onboarding centres it
  /// above the card, because there the card *is* the subject.
  final Alignment glowCenter;

  /// How far the glow reaches, as a fraction of the shorter side.
  final double glowRadius;

  final double glowOpacity;

  const CanvasBackdrop({
    super.key,
    required this.child,
    this.glowCenter = const Alignment(-0.4, -1.1),
    this.glowRadius = 1.1,
    this.glowOpacity = 0.09,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return DecoratedBox(
          decoration: BoxDecoration(color: themeState.bgPrimary),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: glowCenter,
                radius: glowRadius,
                colors: [
                  themeState.primary.withValues(alpha: glowOpacity),
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
