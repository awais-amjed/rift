import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/feature_header.dart';
import '../../../../common/message_banner.dart';
import '../onboarding_footer.dart';
import '../onboarding_page.dart';

class VaultPasswordView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const VaultPasswordView({
    super.key,
    required this.state,
    required this.onBack,
  });

  @override
  State<VaultPasswordView> createState() => VaultPasswordViewState();
}

class VaultPasswordViewState extends State<VaultPasswordView> {
  final _vaultPasswordController = TextEditingController();

  @override
  void dispose() {
    _vaultPasswordController.dispose();
    super.dispose();
  }

  void _unlock() {
    context.read<SupabaseBackupCubit>().submitVaultPassword(
      _vaultPasswordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = widget.state.isProcessing;

    void back() {
      final cubit = context.read<SupabaseBackupCubit>();
      cubit.dismissPending();
      cubit.signOut();
      widget.onBack();
    }

    return OnboardingPage(
      step: 1,
      stepLabel: 'account',
      onBack: isProcessing ? null : back,
      footer: OnboardingFooter(
        onBack: back,
        backEnabled: !isProcessing,
        primary: AppButton(
          label: 'Unlock',
          isLoading: isProcessing,
          onPressed: isProcessing ? null : _unlock,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FeatureHeader(
            icon: Icons.lock_open_rounded,
            title: 'Unlock your backup',
            subtitle:
                'We found your backup, but it\'s protected by a separately '
                'chosen vault password (privacy mode). Enter it once — '
                'future restores will be automatic.',
          ),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _vaultPasswordController,
                  label: 'Vault password',
                  hint: 'Enter your vault password',
                  obscureText: true,
                  enabled: !isProcessing,
                  autofocus: true,
                  onEditingComplete: isProcessing ? null : _unlock,
                ),
                if (widget.state.error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(
                    message: widget.state.error!,
                    kind: MessageBannerKind.error,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
