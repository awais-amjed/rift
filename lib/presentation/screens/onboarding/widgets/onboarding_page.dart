import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../common/app_button_height.dart';
import '../../../common/centered_scroll_view.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/theme_context.dart';
import 'onboarding_phone_top_bar.dart';
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

  /// The widest a step's content gets, on any window.
  static const double _contentWidth = 512;

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
    final themeState = context.theme;
    return CenteredScrollView(
      // Sized so the welcome, the tallest step, fits the default 1280×720
      // window with its dots showing; it used to need about 790.
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      maxWidth: _contentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(48, 36, 48, 32),
            decoration: BoxDecoration(
              // Translucent, so the canvas glow reads through the card
              // instead of stopping at its edge.
              color: themeState.bgSecondary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(K.radiusCard),
              border: Border.all(color: themeState.borderElevated),
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
                          maxWidth: K.onboardingFormWidth,
                        ),
                        child: footer,
                      ),
                    ],
                  ),
          ),
          if (step != null) ...[
            const SizedBox(height: 16),
            StepDots(step: step!, count: stepCount, label: stepLabel),
          ],
        ],
      ),
    );
  }

  Widget _buildForPhone(BuildContext context) {
    final showTopBar = onBack != null || (step != null && stepLabel != null);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTopBar)
            OnboardingPhoneTopBar(
              onBack: onBack,
              step: step,
              label: stepLabel,
              color: progressColor,
            ),
          Expanded(
            // Centred while it fits, so a short step doesn't cling to the top
            // of a tall screen.
            child: CenteredScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              maxWidth: _contentWidth,
              child: child,
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Center(
                // Full width up to the cap — a loose width would let the
                // buttons shrink to their labels.
                child: ConstrainedBox(
                  constraints: const BoxConstraints.tightFor(
                    width: _contentWidth,
                  ),
                  child: AppButtonHeight(
                    height: K.thumbCtaHeight,
                    child: footer!,
                  ),
                ),
              ),
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
