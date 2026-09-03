import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/resend_confirmation_button.dart';

import '../section_title.dart';
import '../../../../theme/app_text.dart';

class ConfirmEmailPanel extends StatelessWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const ConfirmEmailPanel({
    super.key,
    required this.themeState,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final email = state.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Check Your Email', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          email != null
              ? 'A confirmation link was sent to $email. Click the link, then sign in.'
              : 'A confirmation link was sent to your email. Click the link, then sign in.',
          style: AppText.secondary.copyWith(
            fontSize: 12,
            color: themeState.textTertiary,
            height: 1.5,
          ),
        ),
        if (state.successMessage != null) ...[
          const SizedBox(height: 12),
          MessageBanner(
            message: state.successMessage!,
            kind: MessageBannerKind.success,
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(message: state.error!, kind: MessageBannerKind.error),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            AppButton(
              label: 'Sign In After Confirming',
              onPressed: cubit.clearMessage,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ResendConfirmationButton(
                availableAt: state.resendAvailableAt,
                isProcessing: state.isProcessing,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
