import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/button_footer.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/resend_confirmation_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

/// Settings' "check your email" step, while a new cloud account's address is
/// unconfirmed.
class ConfirmEmailPanel extends StatelessWidget {
  final SupabaseBackupState state;

  const ConfirmEmailPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final cubit = context.read<SupabaseBackupCubit>();
    final email = state.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Check your email'),
        const SizedBox(height: 4),
        Text(
          email != null
              ? 'A confirmation link was sent to $email. Click the link, then sign in.'
              : 'A confirmation link was sent to your email. Click the link, then sign in.',
          style: AppText.secondary.copyWith(
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
        // Sign in is what almost everybody is here to do; Resend is the
        // fallback for the one whose first email never arrived.
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            ResendConfirmationButton(
              availableAt: state.resendAvailableAt,
              isProcessing: state.isProcessing,
            ),
            AppButton(label: 'Sign in', onPressed: cubit.clearMessage),
          ],
        ),
      ],
    );
  }
}
