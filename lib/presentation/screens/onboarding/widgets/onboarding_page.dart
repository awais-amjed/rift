import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_shadows.dart';
import 'step_dots.dart';

/// Shared layout for every onboarding page: a card floating on the canvas,
/// vertically centred while the window is tall enough and scrollable (rather
/// than clipped) when it isn't.
///
/// The card is what makes onboarding feel like the same app as the rest —
/// before the sidebar and panels exist, this is the only chrome there is.
class OnboardingPage extends StatelessWidget {
  final Widget child;

  /// Zero-based step, for the dots under the card. Null hides them — used by
  /// the interstitial views (email confirmation) that aren't their own step.
  final int? step;

  static const int stepCount = 3;

  const OnboardingPage({super.key, required this.child, this.step});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
                          decoration: BoxDecoration(
                            color: themeState.bgSecondary,
                            borderRadius: BorderRadius.circular(K.radiusDialog),
                            border: Border.all(color: themeState.borderPrimary),
                            boxShadow: AppShadows.dialog,
                          ),
                          child: child,
                        ),
                        if (step != null) ...[
                          const SizedBox(height: 20),
                          StepDots(step: step!, count: stepCount),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
