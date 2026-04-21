import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../theme/custom_colors.dart';

/// First step of onboarding — welcome & app overview.
class WelcomeStep extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onRestore;

  const WelcomeStep({super.key, required this.onContinue, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: CustomColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.headset_mic_rounded,
              size: 40,
              color: CustomColors.primary,
            ),
          ),

          const SizedBox(height: 32),

          // Title
          Text(
            'Welcome to Rift',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 12),

          // Subtitle
          Text(
            'Your space to hang out.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: CustomColors.primary,
            ),
          ),

          const SizedBox(height: 24),

          // Description
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Rift lets you voice chat, share screens, and hang out '
              'in communities — all self-hosted and on your terms.\n\n'
              'To get started, we\'ll set up your account with a password. '
              'No email or phone number needed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: theme.textTertiary,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Feature pills
          _FeaturePillRow(theme: theme),

          const SizedBox(height: 40),

          // CTA
          AppButton(
            label: 'Get Started',
            onPressed: onContinue,
            icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
          ),

          const SizedBox(height: 12),

          AppButton(
            label: 'Restore from Backup',
            variant: AppButtonVariant.secondary,
            onPressed: onRestore,
            icon: Icon(
              Icons.cloud_download_rounded,
              size: 18,
              color: theme.textSecondary,
            ),
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
        _pill(Icons.mic_rounded, 'Voice Chat'),
        _pill(Icons.screen_share_rounded, 'Screen Sharing'),
        _pill(Icons.forum_rounded, 'Channels'),
        _pill(Icons.dns_rounded, 'Self-Hosted'),
      ],
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: CustomColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
