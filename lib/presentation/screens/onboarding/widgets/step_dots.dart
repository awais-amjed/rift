import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';

/// Progress through onboarding, as dots under the card, with a word for
/// where you are: "Step 2 of 2 · account".
///
/// The current step is a stretched pill rather than a bigger dot: it says
/// "you are here" without implying the other steps are smaller things.
class StepDots extends StatelessWidget {
  final int step;
  final int count;
  final String? label;

  const StepDots({
    super.key,
    required this.step,
    required this.count,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: AppMotion.state,
                curve: Curves.easeOut,
                width: i == step ? 18 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: i == step
                      ? themeState.primary
                      : themeState.borderElevated,
                  borderRadius: BorderRadius.circular(K.radiusPill),
                ),
              ),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                'Step ${step + 1} of $count · $label',
                style: AppText.label.copyWith(color: themeState.textTertiary),
              ),
            ],
          ],
        );
      },
    );
  }
}
