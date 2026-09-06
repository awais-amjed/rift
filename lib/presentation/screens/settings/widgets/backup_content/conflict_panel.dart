import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/message_banner.dart';

import '../section_title.dart';
import '../../../../theme/app_text.dart';
import '../../../../common/button_footer.dart';
import '../../../../theme/theme_context.dart';

class ConflictPanel extends StatelessWidget {
  final SupabaseBackupState state;

  const ConflictPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = state.isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Two identities'),
        const SizedBox(height: 4),
        Text(
          'Your account already has a cloud backup, and this device has its '
          'own vault. Choose which one to keep.',
          style: AppText.secondary.copyWith(
            color: themeState.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        // The consequence first, then the choice is named in the buttons.
        const MessageBanner(
          message:
              "Whichever you don't keep is overwritten and cannot be "
              'recovered.',
          kind: MessageBannerKind.caution,
        ),
        const SizedBox(height: 16),
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            AppButton(
              label: 'Keep cloud',
              variant: AppButtonVariant.secondary,
              onPressed: isProcessing ? null : cubit.restoreCloudBackup,
            ),
            AppButton(
              label: 'Keep this device',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : cubit.keepLocalVault,
            ),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.error!, kind: MessageBannerKind.error),
        ],
      ],
    );
  }
}
