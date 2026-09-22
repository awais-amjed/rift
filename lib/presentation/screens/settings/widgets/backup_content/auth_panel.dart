import 'package:flutter/material.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/button_footer.dart';
import '../../../../common/handle_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/segmented_control.dart';
import '../../../../common/supabase_auth_form_state.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

/// Sign in or create a cloud backup account, from Settings.
class AuthPanel extends StatefulWidget {
  final SupabaseBackupState state;

  const AuthPanel({super.key, required this.state});

  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<AuthPanel>
    with SupabaseAuthFormState<AuthPanel> {
  @override
  Widget build(BuildContext context) {
    final isProcessing = widget.state.isProcessing;
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SegmentedControl<bool>(
            value: isSignUp,
            onChanged: isProcessing
                ? null
                : (signUp) => setState(() => isSignUp = signUp),
            options: const [
              SegmentOption(value: false, label: 'Sign in'),
              SegmentOption(value: true, label: 'Create account'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionTitle(
          label: isSignUp
              ? 'Create a backup account'
              : 'Sign in to cloud backup',
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
          onEditingComplete: (isProcessing || isSignUp)
              ? null
              : submitCredentials,
        ),
        if (isSignUp) ...[
          const SizedBox(height: 12),
          HandleField(
            controller: handleController,
            enabled: !isProcessing,
            onEditingComplete: isProcessing ? null : submitCredentials,
          ),
        ],
        if (widget.state.error != null) ...[
          const SizedBox(height: 10),
          MessageBanner(
            message: widget.state.error!,
            kind: MessageBannerKind.error,
          ),
        ],
        const SizedBox(height: 16),
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            AppButton(
              label: isSignUp ? 'Create account' : 'Sign in',
              isLoading: isProcessing,
              onPressed: isProcessing ? null : submitCredentials,
            ),
          ],
        ),
      ],
    );
  }
}
