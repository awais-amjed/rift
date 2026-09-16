import 'package:flutter/material.dart';

import '../../../common/app_button.dart';
import '../../../common/button_footer.dart';
import '../../../responsive/shell_scope.dart';

/// The way on from an onboarding step, and the way back.
///
/// Laid out for the room there is. In a desktop's card the two sit as a pair,
/// Back then the commit, with any secondary link under them. On a phone the
/// commit spans the screen at the thumb height — see `OnboardingPage`, which
/// pins it — and Back is the arrow at the top of the page instead, so it is
/// not drawn here at all.
class OnboardingFooter extends StatelessWidget {
  final Widget primary;

  /// Back, on a desktop. Null draws no Back button there.
  final VoidCallback? onBack;

  /// Everything a step would otherwise put after its buttons — a "Forgotten
  /// your password?" link, a resend countdown.
  final Widget? secondary;

  /// False while the step is busy: Back stays on screen but can't be pressed.
  final bool backEnabled;

  const OnboardingFooter({
    super.key,
    required this.primary,
    this.onBack,
    this.secondary,
    this.backEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final compact = context.layoutMode.isCompact;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact || onBack == null)
          SizedBox(width: double.infinity, child: primary)
        else
          ButtonFooter(
            buttons: [
              AppButton(
                label: 'Back',
                variant: AppButtonVariant.secondary,
                onPressed: backEnabled ? onBack : null,
              ),
              primary,
            ],
          ),
        if (secondary != null) ...[
          SizedBox(height: compact ? 4 : 12),
          Center(child: secondary!),
        ],
      ],
    );
  }
}
