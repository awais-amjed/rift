import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';
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
    return BlocProvider(
      create: (_) =>
          SupabaseBackupCubit(vaultCubit: context.read<VaultCubit>()),
      child: _BackupBody(themeState: themeState),
    );
  }
}

class _BackupBody extends StatelessWidget {
  final ThemeState themeState;

  const _BackupBody({required this.themeState});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        if (state.isSignedIn) {
          return _SignedInPanel(themeState: themeState, state: state);
        }
        if (state.needsEmailConfirmation) {
          return _ConfirmEmailPanel(themeState: themeState, email: state.email);
        }
        return _AuthPanel(themeState: themeState, state: state);
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
                style: const TextStyle(
                  fontSize: 12,
                  color: CustomColors.primary,
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
                onPressed: isProcessing ? null : cubit.signOut,
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

