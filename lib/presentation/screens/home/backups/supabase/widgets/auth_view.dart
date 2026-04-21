import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../theme/custom_colors.dart';
import 'message_banner.dart';

/// Sign-up / sign-in form shown when the user is not yet authenticated.
class AuthView extends StatefulWidget {
  final SupabaseBackupState state;

  const AuthView({super.key, required this.state});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
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
          style: TextStyle(fontSize: 13, height: 1.5, color: theme.textTertiary),
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

        if (widget.state.error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(message: widget.state.error!, isError: true),
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
          onPressed:
              isProcessing ? null : () => setState(() => _isSignUp = !_isSignUp),
          child: Text(
            _isSignUp
                ? 'Already have an account? Sign in'
                : "Don't have an account? Sign up",
            style: const TextStyle(fontSize: 13, color: CustomColors.primary),
          ),
        ),
      ],
    );
  }
}

