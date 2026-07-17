
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';

import 'section_title.dart';
class AuthPanel extends StatefulWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const AuthPanel({required this.themeState, required this.state});

  @override
  State<AuthPanel> createState() => AuthPanelState();
}

class AuthPanelState extends State<AuthPanel> {
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
        SectionTitle(
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

