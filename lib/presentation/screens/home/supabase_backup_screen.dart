import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../common/app_button.dart';
import '../../common/app_text_field.dart';
import '../../theme/custom_colors.dart';

/// Full-screen (or routed) view for managing Supabase cloud backups.
///
/// Flow:
///   • Not signed in → show sign-up / sign-in form
///   • Signed in     → show "Save backup" and "Import backup" actions
class SupabaseBackupScreen extends StatelessWidget {
  const SupabaseBackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SupabaseBackupCubit(
        vaultCubit: context.read<VaultCubit>(),
      ),
      child: const _SupabaseBackupView(),
    );
  }
}

class _SupabaseBackupView extends StatelessWidget {
  const _SupabaseBackupView();

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Cloud Backup',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
          ),
        ),
        leading: BackButton(color: theme.textSecondary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.borderPrimary),
        ),
      ),
      body: BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
        builder: (context, state) {
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: state.isSignedIn
                      ? _SignedInView(state: state)
                      : _AuthView(state: state),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Auth view (sign-up / sign-in) ─────────────────────────────────────────────

class _AuthView extends StatefulWidget {
  final SupabaseBackupState state;

  const _AuthView({required this.state});

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
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
    final theme = context.read<ThemeCubit>().state;
    final isProcessing = widget.state.isProcessing;

    return Column(
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
            Icons.cloud_upload_rounded,
            size: 32,
            color: CustomColors.primary,
          ),
        ),

        const SizedBox(height: 24),

        Text(
          _isSignUp ? 'Create Backup Account' : 'Sign In to Cloud Backup',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.3,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          _isSignUp
              ? 'Your encrypted backup is stored on our central server. '
                  'Only you can decrypt it.'
              : 'Sign in to upload or restore your encrypted backup.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: theme.textTertiary,
          ),
        ),

        const SizedBox(height: 32),

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
          label: 'Password',
          hint: 'Enter your password',
          obscureText: true,
          enabled: !isProcessing,
          onEditingComplete: isProcessing ? null : _submit,
        ),

        // Error / success messages
        if (widget.state.error != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(
            message: widget.state.error!,
            isError: true,
          ),
        ],

        const SizedBox(height: 24),

        AppButton(
          label: _isSignUp ? 'Create Account' : 'Sign In',
          expanded: true,
          isLoading: isProcessing,
          onPressed: isProcessing ? null : _submit,
        ),

        const SizedBox(height: 16),

        TextButton(
          onPressed: isProcessing
              ? null
              : () => setState(() => _isSignUp = !_isSignUp),
          child: Text(
            _isSignUp
                ? 'Already have an account? Sign in'
                : 'Don\'t have an account? Sign up',
            style: const TextStyle(
              fontSize: 13,
              color: CustomColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Signed-in view ────────────────────────────────────────────────────────────

class _SignedInView extends StatefulWidget {
  final SupabaseBackupState state;

  const _SignedInView({required this.state});

  @override
  State<_SignedInView> createState() => _SignedInViewState();
}

class _SignedInViewState extends State<_SignedInView> {
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
        // Signed-in banner
        Container(
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
                  'Signed in as ${widget.state.email ?? 'unknown'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: isProcessing ? null : cubit.signOut,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 32),
                ),
                child: const Text(
                  'Sign out',
                  style: TextStyle(
                    fontSize: 12,
                    color: CustomColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── Save backup ─────────────────────────────────────────
        _SectionHeader(
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

        // ── Import backup ────────────────────────────────────────
        _SectionHeader(
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
                            vaultPassword:
                                _importPasswordController.text,
                          ),
                ),
              ),
            ],
          ),
        ],

        // Error / success messages
        if (widget.state.error != null) ...[
          const SizedBox(height: 16),
          _MessageBanner(message: widget.state.error!, isError: true),
        ],
        if (widget.state.successMessage != null) ...[
          const SizedBox(height: 16),
          _MessageBanner(
            message: widget.state.successMessage!,
            isError: false,
          ),
        ],
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: CustomColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: CustomColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: theme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const _MessageBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? CustomColors.error : CustomColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

