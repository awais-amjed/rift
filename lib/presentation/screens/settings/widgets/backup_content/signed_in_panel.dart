import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/button_footer.dart';
import '../../../../common/masked_email_text.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

class SignedInPanel extends StatelessWidget {
  final SupabaseBackupState state;

  const SignedInPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = state.isProcessing;
    final theme = themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Signed-in banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: CustomColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(
              color: CustomColors.success.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_done_rounded,
                size: 16,
                color: CustomColors.success,
              ),
              const SizedBox(width: 8),
              // Only who you are. Signing out is an action against this
              // device, and it lives with the other one of those, under
              // "This device" below.
              Expanded(
                child: MaskedEmailText(
                  email: state.email,
                  prefix: 'Signed in as ',
                  style: AppText.secondary.copyWith(color: theme.textSecondary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Save backup ────────────────────────────────────────
        SectionTitle(label: 'Cloud'),
        const SizedBox(height: 4),
        Text(
          'Upload your current encrypted vault backup to the cloud. '
          'Your password is never sent.',
          style: AppText.secondary.copyWith(
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            AppButton(
              label: 'Save',
              isLoading: isProcessing,
              icon: const Icon(Icons.cloud_upload_rounded, size: 15),
              onPressed: isProcessing ? null : cubit.saveBackupToCloud,
            ),
            AppButton(
              label: 'Restore',
              variant: AppButtonVariant.secondary,
              onPressed: isProcessing
                  ? null
                  : () => cubit.importBackupFromCloud(),
            ),
          ],
        ),

        // Messages
        if (state.error != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.error!, kind: MessageBannerKind.error),
        ],
        if (state.successMessage != null) ...[
          const SizedBox(height: 14),
          MessageBanner(
            message: state.successMessage!,
            kind: MessageBannerKind.success,
          ),
        ],
      ],
    );
  }
}
