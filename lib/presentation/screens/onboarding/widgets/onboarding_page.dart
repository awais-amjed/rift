import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button_height.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_text.dart';
import 'step_dots.dart';

/// Shared layout for every onboarding page: a card floating on the canvas,
/// vertically centred while the window is tall enough and scrollable (rather
/// than clipped) when it isn't.
///
/// The card is what makes onboarding feel like the same app as the rest —
/// before the sidebar and panels exist, this is the only chrome there is.
///
/// A phone gets no card. A card inside a 390px screen is margins and a border
/// around the same content, so there the step is the screen: the way back and
/// the progress across the top, the content in the middle, and [footer] pinned
/// at the bottom where a thumb is, at the thumb height. The canvas glow stays.
class OnboardingPage extends StatelessWidget {
  final Widget child;

  /// Zero-based step, for the dots under the card. Null hides them — used by
  /// the interstitial views (email confirmation) that aren't their own step.
  final int? step;

  /// What this step is — "account", "vault" — so the dots say which of the
  /// two paths you are on rather than counting three steps that are never
  /// all walked.
  final String? stepLabel;

  /// Welcome, then one step: the account or the vault.
  static const int stepCount = 2;

  /// The step's actions — see [OnboardingFooter]. Under the content in the
  /// card; pinned to the bottom of a phone.
  final Widget? footer;

  /// The back arrow at the top of a phone's page. A desktop's Back is in the
  /// footer instead.
  final VoidCallback? onBack;

  /// The progress bar's colour on a phone, for a step that is claiming safety
  /// rather than counting — the vault's green.
  final Color? progressColor;

  const OnboardingPage({
    super.key,
    required this.child,
    this.step,
    this.stepLabel,
    this.footer,
    this.onBack,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact) return _buildForPhone(context);
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
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(48, 44, 48, 40),
                          decoration: BoxDecoration(
                            // Translucent, so the canvas glow reads through
                            // the card instead of stopping at its edge.
                            color: themeState.bgSecondary.withValues(
                              alpha: 0.85,
                            ),
                            borderRadius: BorderRadius.circular(K.radiusCard),
                            border: Border.all(
                              color: themeState.borderElevated,
                            ),
                            boxShadow: AppShadows.dialog,
                          ),
                          child: footer == null
                              ? child
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    child,
                                    const SizedBox(height: 24),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 360,
                                      ),
                                      child: footer,
                                    ),
                                  ],
                                ),
                        ),
                        if (step != null) ...[
                          const SizedBox(height: 20),
                          StepDots(
                            step: step!,
                            count: stepCount,
                            label: stepLabel,
                          ),
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

  Widget _buildForPhone(BuildContext context) {
    final showTopBar = onBack != null || (step != null && stepLabel != null);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTopBar)
            _PhoneTopBar(
              onBack: onBack,
              step: step,
              label: stepLabel,
              color: progressColor,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: ConstrainedBox(
                  // Centred while it fits, so a short step doesn't cling to
                  // the top of a tall screen.
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32,
                  ),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: AppButtonHeight(height: K.thumbCtaHeight, child: footer!),
            ),
          // The welcome has no top bar to carry progress, so it keeps its
          // dots at the foot.
          if (!showTopBar && step != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: StepDots(step: step!, count: stepCount),
              ),
            ),
        ],
      ),
    );
  }
}

/// A phone's onboarding header: the way back, and how far along you are as a
/// bar with the step named under it.
class _PhoneTopBar extends StatelessWidget {
  final VoidCallback? onBack;
  final int? step;
  final String? label;
  final Color? color;

  const _PhoneTopBar({
    required this.onBack,
    required this.step,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeCubit>().state;
    final step = this.step;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        spacing: 8,
        children: [
          SizedBox.square(
            dimension: K.touchTargetMin,
            child: onBack == null
                ? null
                : IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 22,
                      color: theme.textSecondary,
                    ),
                  ),
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
