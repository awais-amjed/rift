import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';
import '../../../common/restore_file_dialog.dart';
import '../../../theme/custom_colors.dart';

/// Backup tab content rendered inside the settings dialog.
///
/// Provides:
/// - Sign up / sign in to the central Supabase server
/// - Save current encrypted backup to the cloud
class BackupContent extends StatelessWidget {
  final ThemeState themeState;

  const BackupContent({super.key, required this.themeState});

  @override
  Widget build(BuildContext context) {
    // Uses the app-global SupabaseBackupCubit provided in main.dart.
    return _BackupBody(themeState: themeState);
  }
}

class _BackupBody extends StatelessWidget {
  final ThemeState themeState;

  const _BackupBody({required this.themeState});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        final Widget cloudPanel;
        if (state.cloudBackupConflict) {
          cloudPanel = _ConflictPanel(themeState: themeState, state: state);
        } else if (state.needsVaultPassword) {
          cloudPanel = _VaultPasswordPanel(themeState: themeState, state: state);
        } else if (state.isSignedIn) {
          cloudPanel = _SignedInPanel(themeState: themeState, state: state);
        } else if (state.needsEmailConfirmation) {
          cloudPanel =
              _ConfirmEmailPanel(themeState: themeState, email: state.email);
        } else {
          cloudPanel = _AuthPanel(themeState: themeState, state: state);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cloudPanel,
            const SizedBox(height: 28),
            _FileBackupPanel(themeState: themeState),
          ],
        );
      },
    );
  }
}

// ── Auth panel ────────────────────────────────────────────────────────────────

class _AuthPanel extends StatefulWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const _AuthPanel({required this.themeState, required this.state});

  @override
  State<_AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<_AuthPanel> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final cubit = context.read<SupabaseBackupCubit>();
    if (_isSignUp) {
      cubit.signUp(email: email, password: password);
    } else {
      cubit.signIn(email: email, password: password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = widget.state.isProcessing;
    final theme = widget.themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          label: _isSignUp
              ? 'Create Backup Account'
              : 'Sign In to Cloud Backup',
          themeState: theme,
        ),
        const SizedBox(height: 4),
        Text(
          _isSignUp
              ? 'Your encrypted backup is stored securely. Only you can decrypt it.'
              : 'Authenticate to upload or restore your encrypted vault backup.',
          style: TextStyle(
            fontSize: 12,
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        AppTextField(
          controller: _emailController,
          label: 'Email',
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          enabled: !isProcessing,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'Enter your password',
          obscureText: true,
          enabled: !isProcessing,
          onEditingComplete: isProcessing ? null : _submit,
        ),
        if (widget.state.error != null) ...[
          const SizedBox(height: 10),
          MessageBanner(message: widget.state.error!, isError: true),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            AppButton(
              label: _isSignUp ? 'Create Account' : 'Sign In',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : _submit,
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: isProcessing
                  ? null
                  : () => setState(() => _isSignUp = !_isSignUp),
              child: Text(
                _isSignUp ? 'Already have an account?' : 'Create an account',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Signed-in panel ───────────────────────────────────────────────────────────

class _SignedInPanel extends StatelessWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const _SignedInPanel({required this.themeState, required this.state});

  /// Signs out of the account AND removes the vault + server list from this
  /// device, returning to onboarding. The cloud backup is untouched, so
  /// signing back in restores everything.
  Future<void> _signOutOfDevice(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of this device?'),
        content: const Text(
          'Your encrypted cloud backup stays safe. The vault and server '
          'list on this device will be removed — sign back in to restore '
          'them automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: CustomColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final backupCubit = context.read<SupabaseBackupCubit>();
    final serverCubit = context.read<ServerCubit>();
    final vaultCubit = context.read<VaultCubit>();
    final navigator = Navigator.of(context);

    await backupCubit.signOut();
    await serverCubit.reset();
    await vaultCubit.resetVault();

    // Close the settings dialog — the router now shows onboarding.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
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
            borderRadius: BorderRadius.circular(8),
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
              Expanded(
                child: Text(
                  'Signed in as ${state.email ?? 'unknown'}',
                  style: TextStyle(fontSize: 12, color: theme.textSecondary),
                ),
              ),
              TextButton(
                onPressed:
                    isProcessing ? null : () => _signOutOfDevice(context),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Sign out',
                  style: TextStyle(fontSize: 11, color: CustomColors.error),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Save backup ────────────────────────────────────────
        _SectionTitle(label: 'Save Backup', themeState: theme),
        const SizedBox(height: 4),
        Text(
          'Upload your current encrypted vault backup to the cloud. '
          'Your password is never sent.',
          style: TextStyle(
            fontSize: 12,
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            AppButton(
              label: 'Save to Cloud',
              isLoading: isProcessing,
              icon: const Icon(
                Icons.cloud_upload_rounded,
                size: 15,
                color: Colors.white,
              ),
              onPressed: isProcessing ? null : cubit.saveBackupToCloud,
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Restore from Cloud',
              variant: AppButtonVariant.secondary,
              onPressed:
                  isProcessing ? null : () => cubit.importBackupFromCloud(),
            ),
          ],
        ),


        // Messages
        if (state.error != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.error!, isError: true),
        ],
        if (state.successMessage != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.successMessage!, isError: false),
        ],
      ],
    );
  }
}

// ── Conflict panel ────────────────────────────────────────────────────────────

/// Shown when sign-in found a cloud backup while a local vault already exists.
class _ConflictPanel extends StatelessWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const _ConflictPanel({required this.themeState, required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = state.isProcessing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'Backup Conflict', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          'Your account already has a cloud backup, but this device has its '
          'own vault. Choose which identity to keep — the other one is '
          'overwritten.',
          style: TextStyle(
            fontSize: 12,
            color: themeState.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            AppButton(
              label: 'Keep This Device',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : cubit.keepLocalVault,
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Restore Cloud Backup',
              variant: AppButtonVariant.secondary,
              onPressed: isProcessing ? null : cubit.restoreCloudBackup,
            ),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: 14),
          MessageBanner(message: state.error!, isError: true),
        ],
      ],
    );
  }
}

// ── Vault password panel ──────────────────────────────────────────────────────

/// Shown when the cloud backup needs a manually chosen vault password.
class _VaultPasswordPanel extends StatefulWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const _VaultPasswordPanel({required this.themeState, required this.state});

  @override
  State<_VaultPasswordPanel> createState() => _VaultPasswordPanelState();
}

class _VaultPasswordPanelState extends State<_VaultPasswordPanel> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = widget.state.isProcessing;
    final theme = widget.themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'Unlock Cloud Backup', themeState: theme),
        const SizedBox(height: 4),
        Text(
          'This backup is protected by a separately chosen vault password '
          '(privacy mode). Enter it once — it will be re-encrypted under '
          'your account password afterwards.',
          style: TextStyle(
            fontSize: 12,
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _passwordController,
          label: 'Vault Password',
          hint: 'Enter your vault password',
          obscureText: true,
          enabled: !isProcessing,
          onEditingComplete: isProcessing
              ? null
              : () => cubit.submitVaultPassword(_passwordController.text),
        ),
        if (widget.state.error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(message: widget.state.error!, isError: true),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            AppButton(
              label: 'Unlock',
              isLoading: isProcessing,
              onPressed: isProcessing
                  ? null
                  : () => cubit.submitVaultPassword(_passwordController.text),
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: isProcessing ? null : cubit.dismissPending,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Local file backup panel ───────────────────────────────────────────────────

/// Export/restore the encrypted backup as a local file — works without an
/// account (the privacy-mode recovery path).
class _FileBackupPanel extends StatefulWidget {
  final ThemeState themeState;

  const _FileBackupPanel({required this.themeState});

  @override
  State<_FileBackupPanel> createState() => _FileBackupPanelState();
}

class _FileBackupPanelState extends State<_FileBackupPanel> {
  bool _isExporting = false;

  Future<void> _exportToFile() async {
    setState(() => _isExporting = true);
    try {
      final vaultCubit = context.read<VaultCubit>();
      final export = await vaultCubit.exportBackup();
      if (!export.success || export.content == null) {
        HelperMethods.showError(
          error: export.error ?? 'Failed to export backup',
        );
        return;
      }

      final location = await getSaveLocation(
        suggestedName: 'rift-backup.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Rift backup', extensions: ['json']),
        ],
      );
      if (location == null) return; // user cancelled

      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(export.content!)),
        mimeType: 'application/json',
      );
      await file.saveTo(location.path);

      HelperMethods.showToast(
        title: 'Backup exported',
        description: 'Encrypted backup saved to ${location.path}',
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _restoreFromFile() {
    showCustomDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<VaultCubit>(),
        child: const RestoreFileDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'Backup File', themeState: theme),
        const SizedBox(height: 4),
        Text(
          'Export your encrypted backup as a file, or restore from one. '
          'Works entirely offline — no account needed.',
          style: TextStyle(
            fontSize: 12,
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            AppButton(
              label: 'Export to File',
              isLoading: _isExporting,
              icon: const Icon(
                Icons.save_alt_rounded,
                size: 15,
                color: Colors.white,
              ),
              onPressed: _isExporting ? null : _exportToFile,
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Restore from File',
              variant: AppButtonVariant.secondary,
              onPressed: _isExporting ? null : _restoreFromFile,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Email confirmation panel ──────────────────────────────────────────────────

class _ConfirmEmailPanel extends StatelessWidget {
  final ThemeState themeState;
  final String? email;

  const _ConfirmEmailPanel({required this.themeState, this.email});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'Check Your Email', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          email != null
              ? 'A confirmation link was sent to $email. Click the link, then sign in.'
              : 'A confirmation link was sent to your email. Click the link, then sign in.',
          style: TextStyle(
            fontSize: 12,
            color: themeState.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Sign In After Confirming',
          onPressed: cubit.clearMessage,
        ),
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String label;
  final ThemeState themeState;

  const _SectionTitle({required this.label, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: themeState.textPrimary,
      ),
    );
  }
}

