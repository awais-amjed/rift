import 'package:flutter/material.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/supabase_auth_form_state.dart';

import '../section_title.dart';
import '../../../../theme/app_text.dart';
import '../../../../common/button_footer.dart';
import '../../../../theme/theme_context.dart';

class AuthPanel extends StatefulWidget {
  final SupabaseBackupState state;

  const AuthPanel({super.key, required this.state});

  @override
  State<AuthPanel> createState() => AuthPanelState();
}

class AuthPanelState extends State<AuthPanel>
    with SupabaseAuthFormState<AuthPanel> {
  @override
  Widget build(BuildContext context) {
    final isProcessing = widget.state.isProcessing;
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          label: isSignUp ? 'Create Backup Account' : 'Sign In to Cloud Backup',
        ),
        const SizedBox(height: 4),
        Text(
          isSignUp
              ? 'Your encrypted backup is stored securely. Only you can decrypt it.'
              : 'Authenticate to upload or restore your encrypted vault backup.',
          style: AppText.secondary.copyWith(
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
          MessageBanner(
            message: widget.state.error!,
            kind: MessageBannerKind.error,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: isProcessing ? null : toggleAuthMode,
              child: Text(
                isSignUp ? 'Already have an account?' : 'Create an account',
                style: AppText.secondary.copyWith(color: theme.primary),
              ),
            ),
            const Spacer(),
            ButtonFooter(
              buttons: [
                AppButton(
                  label: isSignUp ? 'Create account' : 'Sign in',
                  isLoading: isProcessing,
                  onPressed: isProcessing ? null : submitCredentials,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
