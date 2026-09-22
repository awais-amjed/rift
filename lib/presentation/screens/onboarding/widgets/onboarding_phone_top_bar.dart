import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../common/back_chevron_button.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'onboarding_page.dart';

/// A phone's onboarding header: the way back, and how far along you are as a
/// bar with the step named under it.
class OnboardingPhoneTopBar extends StatelessWidget {
  final VoidCallback? onBack;
  final int? step;
  final String? label;
  final Color? color;

  const OnboardingPhoneTopBar({
    super.key,
    required this.onBack,
    required this.step,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final step = this.step;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        spacing: 8,
        children: [
          SizedBox.square(
            dimension: K.touchTargetMin,
            child: onBack == null ? null : BackChevronButton(onPressed: onBack),
          ),
          if (step != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Row(
                    spacing: 4,
                    children: [
                      for (var i = 0; i < OnboardingPage.stepCount; i++)
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: i <= step
                                  ? (color ?? theme.primary)
                                  : theme.borderElevated,
                              borderRadius: BorderRadius.circular(K.radiusPill),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (label != null)
                    Text(
                      'Step ${step + 1} of ${OnboardingPage.stepCount} · $label',
                      style: AppText.label.copyWith(color: theme.textTertiary),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
