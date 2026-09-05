import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../theme/custom_colors.dart';
import 'message_banner.dart';
import 'section_header.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../../data/constants.dart';

/// Actions view shown when the user is signed in to the backup server.
///
/// Provides the "Save backup" control.
class SignedInView extends StatelessWidget {
  final SupabaseBackupState state;

  const SignedInView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = state.isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Signed-in banner ──────────────────────────────────
        _SignedInBanner(
          email: state.email,
          isProcessing: isProcessing,
          onSignOut: cubit.signOut,
        ),

        const SizedBox(height: 28),

        // ── Save backup ───────────────────────────────────────
        const SectionHeader(
          icon: Icons.cloud_upload_outlined,
          title: 'Save Backup to Cloud',
          description:
              'Uploads your current encrypted backup to the central server. '
              'Your password is never sent — only the encrypted blob.',
        ),

        const SizedBox(height: 16),

        AppButton(
          label: 'Save Backup',
          expanded: true,
          isLoading: isProcessing,
          icon: const Icon(
            Icons.cloud_upload_rounded,
            size: 16,
            color: Colors.white,
          ),
          onPressed: isProcessing ? null : cubit.saveBackupToCloud,
        ),

        if (state.error != null) ...[
          const SizedBox(height: 16),
          MessageBanner(message: state.error!, kind: MessageBannerKind.error),
        ],
        if (state.successMessage != null) ...[
          const SizedBox(height: 16),
          MessageBanner(
            message: state.successMessage!,
            kind: MessageBannerKind.success,
          ),
        ],
      ],
    );
  }
}

// ── Private sub-widget ────────────────────────────────────────────────────────

class _SignedInBanner extends StatelessWidget {
  final String? email;
  final bool isProcessing;
  final VoidCallback onSignOut;

  const _SignedInBanner({
    required this.email,
    required this.isProcessing,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CustomColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: CustomColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: CustomColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Signed in as ${email ?? 'unknown'}',
              style: AppText.rowQuiet.copyWith(color: theme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: isProcessing ? null : onSignOut,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 32),
            ),
            child: Text(
              'Sign out',
              style: AppText.secondary.copyWith(color: CustomColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
