import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../theme/custom_colors.dart';
import 'message_banner.dart';
import 'section_header.dart';

/// Actions view shown when the user is signed in to the backup server.
///
/// Provides "Save backup" and "Import backup" controls.
class SignedInView extends StatefulWidget {
  final SupabaseBackupState state;

  const SignedInView({super.key, required this.state});

  @override
  State<SignedInView> createState() => _SignedInViewState();
}

class _SignedInViewState extends State<SignedInView> {
  final _importPasswordController = TextEditingController();
  bool _showImportForm = false;

  @override
  void dispose() {
    _importPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = widget.state.isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Signed-in banner ──────────────────────────────────
        _SignedInBanner(
          email: widget.state.email,
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
          icon: const Icon(Icons.cloud_upload_rounded,
              size: 16, color: Colors.white),
          onPressed: isProcessing ? null : cubit.saveBackupToCloud,
        ),

        const SizedBox(height: 32),

        Divider(color: theme.borderPrimary),

        const SizedBox(height: 32),

        // ── Import backup ─────────────────────────────────────
        const SectionHeader(
          icon: Icons.cloud_download_outlined,
          title: 'Import Backup from Cloud',
          description:
              'Downloads your encrypted backup and restores your vault. '
              'Enter your master password to decrypt it.',
        ),

        const SizedBox(height: 16),

        if (!_showImportForm) ...[
          AppButton(
            label: 'Import Backup',
            expanded: true,
            variant: AppButtonVariant.secondary,
            icon: Icon(Icons.cloud_download_rounded,
                size: 16, color: theme.textSecondary),
            onPressed: isProcessing
                ? null
                : () => setState(() => _showImportForm = true),
          ),
        ] else ...[
          AppTextField(
            controller: _importPasswordController,
            label: 'Master Password',
            hint: 'Enter your vault password',
            obscureText: true,
            enabled: !isProcessing,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.secondary,
                onPressed: isProcessing
                    ? null
                    : () => setState(() {
                          _showImportForm = false;
                          _importPasswordController.clear();
                        }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Import',
                  expanded: true,
                  isLoading: isProcessing,
                  onPressed: isProcessing
                      ? null
                      : () => cubit.importBackupFromCloud(
                            vaultPassword: _importPasswordController.text,
                          ),
                ),
              ),
            ],
          ),
        ],

        if (widget.state.error != null) ...[
          const SizedBox(height: 16),
          MessageBanner(message: widget.state.error!, isError: true),
        ],
        if (widget.state.successMessage != null) ...[
          const SizedBox(height: 16),
          MessageBanner(message: widget.state.successMessage!, isError: false),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CustomColors.success.withValues(alpha: 0.25),
        ),
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
              style: TextStyle(fontSize: 13, color: theme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: isProcessing ? null : onSignOut,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 32),
            ),
            child: const Text(
              'Sign out',
              style: TextStyle(fontSize: 12, color: CustomColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

