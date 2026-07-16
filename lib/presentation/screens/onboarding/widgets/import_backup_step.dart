import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';
import '../../../theme/custom_colors.dart';

/// Onboarding step for restoring a vault from a Supabase cloud backup.
///
/// Flow:
///   1. Sign in to the backup server (email + backup password).
///   2. Enter the master vault password used when the backup was created.
///   3. Import — the vault is decrypted and the app transitions to [AuthStatus.unlocked].
class ImportBackupStep extends StatelessWidget {
  final VoidCallback onBack;

  const ImportBackupStep({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    // Uses the app-global SupabaseBackupCubit provided in main.dart.
    return _ImportBackupBody(onBack: onBack);
  }
}

class _ImportBackupBody extends StatelessWidget {
  final VoidCallback onBack;

  const _ImportBackupBody({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
      builder: (context, state) {
        if (state.needsEmailConfirmation) {
          return _EmailConfirmationView(onBack: onBack);
        }
        if (state.isSignedIn) {
          return _ImportVaultView(state: state, onBack: onBack);
        }
        return _SignInView(state: state, onBack: onBack);
      },
    );
  }
}

// ── Step 1: Sign in ────────────────────────────────────────────────────────────

class _SignInView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const _SignInView({required this.state, required this.onBack});

  @override
  State<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<_SignInView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<SupabaseBackupCubit>().signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final isProcessing = widget.state.isProcessing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CustomColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.cloud_download_rounded,
              size: 32,
              color: CustomColors.primary,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Restore from Backup',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 8),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              'Sign in to your backup account to download '
              'your encrypted vault.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.textTertiary,
              ),
            ),
          ),

          const SizedBox(height: 32),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  enabled: !isProcessing,
                  autofocus: true,
                ),

                const SizedBox(height: 16),

                AppTextField(
                  controller: _passwordController,
                  label: 'Backup Account Password',
                  hint: 'Enter your backup account password',
                  obscureText: true,
                  enabled: !isProcessing,
                  onEditingComplete: isProcessing ? null : _submit,
                ),

                if (widget.state.error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(message: widget.state.error!, isError: true),
                ],

                const SizedBox(height: 24),

                Row(
                  children: [
                    AppButton(
                      label: 'Back',
                      variant: AppButtonVariant.secondary,
                      onPressed: isProcessing ? null : widget.onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Sign In',
                        expanded: true,
                        isLoading: isProcessing,
                        onPressed: isProcessing ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 2: Enter vault password & import ─────────────────────────────────────

class _ImportVaultView extends StatefulWidget {
  final SupabaseBackupState state;
  final VoidCallback onBack;

  const _ImportVaultView({required this.state, required this.onBack});

  @override
  State<_ImportVaultView> createState() => _ImportVaultViewState();
}

class _ImportVaultViewState extends State<_ImportVaultView> {
  final _vaultPasswordController = TextEditingController();

  @override
  void dispose() {
    _vaultPasswordController.dispose();
    super.dispose();
  }

  void _import() {
    context.read<SupabaseBackupCubit>().importBackupFromCloud(
          vaultPassword: _vaultPasswordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final cubit = context.read<SupabaseBackupCubit>();
    final isProcessing = widget.state.isProcessing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Signed-in banner
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    size: 16,
                    color: CustomColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Signed in as ${widget.state.email ?? 'unknown'}',
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
          ),

          const SizedBox(height: 32),

          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CustomColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              size: 32,
              color: CustomColors.primary,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Decrypt Your Vault',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 8),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              'Enter the master password you used when you first '
              'created your Rift account. This decrypts your backup locally.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.textTertiary,
              ),
            ),
          ),

          const SizedBox(height: 32),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _vaultPasswordController,
                  label: 'Master Password',
                  hint: 'Enter your vault password',
                  obscureText: true,
                  enabled: !isProcessing,
                  autofocus: true,
                  onEditingComplete: isProcessing ? null : _import,
                ),

                if (widget.state.error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(message: widget.state.error!, isError: true),
                ],

                if (widget.state.successMessage != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(
                    message: widget.state.successMessage!,
                    isError: false,
                  ),
                ],

                const SizedBox(height: 24),

                if (isProcessing) ...[
                  Text(
                    'Downloading and decrypting your backup…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textQuaternary,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                AppButton(
                  label: 'Restore Vault',
                  expanded: true,
                  isLoading: isProcessing,
                  icon: const Icon(
                    Icons.restore_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  onPressed: isProcessing ? null : _import,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Email confirmation pending ────────────────────────────────────────────────

class _EmailConfirmationView extends StatelessWidget {
  final VoidCallback onBack;

  const _EmailConfirmationView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;
    final cubit = context.read<SupabaseBackupCubit>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CustomColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.mark_email_unread_rounded,
              size: 32,
              color: CustomColors.primary,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Check Your Email',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 8),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              'A confirmation link was sent to your email. '
              'Click the link then come back to sign in.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.textTertiary,
              ),
            ),
          ),

          const SizedBox(height: 32),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  label: 'Continue to Sign In',
                  expanded: true,
                  onPressed: cubit.clearMessage,
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Back',
                  variant: AppButtonVariant.secondary,
                  expanded: true,
                  onPressed: onBack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

