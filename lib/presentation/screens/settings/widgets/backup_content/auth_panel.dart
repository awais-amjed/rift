import 'package:flutter/material.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/supabase_auth_form_state.dart';

import 'section_title.dart';

class AuthPanel extends StatefulWidget {
  final ThemeState themeState;
  final SupabaseBackupState state;

  const AuthPanel({super.key, required this.themeState, required this.state});

  @override
  State<AuthPanel> createState() => AuthPanelState();
}

class AuthPanelState extends State<AuthPanel>
    with SupabaseAuthFormState<AuthPanel> {
  @override
  Widget build(BuildContext context) {
    final isProcessing = widget.state.isProcessing;
    final theme = widget.themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          label: isSignUp ? 'Create Backup Account' : 'Sign In to Cloud Backup',
          themeState: theme,
        ),
        const SizedBox(height: 4),
        Text(
          isSignUp
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
          controller: emailController,
          label: 'Email',
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          enabled: !isProcessing,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: passwordController,
          label: 'Password',
          hint: 'Enter your password',
          obscureText: true,
          enabled: !isProcessing,
          onEditingComplete: isProcessing ? null : submitCredentials,
        ),
        if (widget.state.error != null) ...[
          const SizedBox(height: 10),
          MessageBanner(message: widget.state.error!, isError: true),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            AppButton(
              label: isSignUp ? 'Create Account' : 'Sign In',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : submitCredentials,
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: isProcessing ? null : toggleAuthMode,
              child: Text(
                isSignUp ? 'Already have an account?' : 'Create an account',
                style: TextStyle(fontSize: 12, color: theme.primary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
