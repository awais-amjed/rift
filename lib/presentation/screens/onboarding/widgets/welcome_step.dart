import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_mark.dart';
import 'onboarding_page.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';

/// First step of onboarding — welcome & app overview.
class WelcomeStep extends StatelessWidget {
  final VoidCallback onContinueWithAccount;
  final VoidCallback onContinuePrivately;

  const WelcomeStep({
    super.key,
    required this.onContinueWithAccount,
    required this.onContinuePrivately,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return OnboardingPage(
      step: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The brand mark itself, not a tinted tile — this is the first thing
          // anyone sees of Rift, and it should be the same gradient squircle
          // that every server and avatar in the app is cut from.
          const AppMark(size: 76, icon: Icons.headset_mic_rounded, glow: true),

          const SizedBox(height: 28),

          // Title
          Text(
            'Welcome to Rift',
            style: AppText.pageTitle.copyWith(color: theme.textPrimary),
          ),

          const SizedBox(height: 12),

          // Subtitle
          Text(
            'Your space to hang out.',
            style: AppText.sectionTitle.copyWith(color: theme.accentBright),
          ),

          const SizedBox(height: 18),

          // Description
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Rift lets you voice chat, share screens, and hang out '
              'in communities — all self-hosted and on your terms.\n\n'
              'Sign in with an account to keep your identity backed up and '
              'synced across devices — or skip the account entirely and keep '
              'everything on this device.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                height: 1.65,
                color: theme.textTertiary,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Feature pills
          _FeaturePillRow(theme: theme),

          const SizedBox(height: 36),

          // Both CTAs share one width so they read as a stack of choices
          // rather than two buttons that happen to sit above each other.
          // A cap rather than a width: on a phone 340 is wider than what is
          // left after the page's own padding.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              spacing: 10,
              children: [
                AppButton(
                  label: 'Continue with an account',
                  onPressed: onContinueWithAccount,
                  expanded: true,
                  height: 44,
                  icon: const Icon(
                    Icons.arrow_forward,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                AppButton(
                  label: 'Use privacy mode',
                  variant: AppButtonVariant.secondary,
                  onPressed: onContinuePrivately,
                  expanded: true,
                  height: 44,
                  icon: Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'Privacy mode: no email, no central server — your identity '
            'never leaves this device.',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(color: theme.textQuaternary),
          ),
        ],
      ),
    );
  }
}

class _FeaturePillRow extends StatelessWidget {
  final ThemeState theme;

  const _FeaturePillRow({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _pill(Icons.mic_rounded, 'Voice chat'),
        _pill(Icons.screen_share_rounded, 'Screen sharing'),
        _pill(Icons.forum_rounded, 'Channels'),
        _pill(Icons.dns_rounded, 'Self-hosted'),
        // Green, and last, so it reads as the guarantee over the feature list
        // rather than as one more feature in it.
        _pill(
          Icons.lock_outline,
          'End-to-end encrypted',
          color: CustomColors.success,
        ),
      ],
    );
  }

  Widget _pill(IconData icon, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.08) ?? theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusPill),
        border: Border.all(
          color: color?.withValues(alpha: 0.18) ?? theme.borderElevated,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(icon, size: 13, color: color ?? theme.accentBright),
          Text(
            label,
            style: AppText.secondary.copyWith(
              fontWeight: FontWeight.w500,
              color: color ?? theme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
