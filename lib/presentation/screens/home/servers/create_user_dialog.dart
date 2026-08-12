import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';
import '../../../theme/app_text.dart';

/// Dialog shown when user joins a server and needs to create a profile.
class CreateUserDialog extends StatefulWidget {
  final String supabaseUrl;
  final String inviteCode;

  const CreateUserDialog({
    super.key,
    required this.supabaseUrl,
    required this.inviteCode,
  });

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _usernameCtrl.text.trim().isNotEmpty &&
      _displayNameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Step 1: Derive Ed25519 identity + call /register + update SecureStorage vault.
    final result = await context.read<VaultCubit>().registerOnServer(
      supabaseUrl: widget.supabaseUrl,
      inviteCode: widget.inviteCode,
      username: _usernameCtrl.text.trim(),
      displayName: _displayNameCtrl.text.trim(),
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    // Step 2: Persist the new server (token + full context) into HydratedBloc.
    final data = result.data!;
    final token = data['token'] as String;
    context.read<ServerCubit>().addServer(widget.supabaseUrl, token, data);

    HelperMethods.showSuccess(message: 'Account created!');
    Navigator.of(context).pop(true);
  }

  void _dismiss() {
    if (!_isLoading) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return AppModal(
          title: 'Create Your Account',
          subtitle: 'Set up your profile for this server',
          titleIcon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: themeState.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_outline,
              size: 20,
              color: themeState.primary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                MessageBanner(message: _error!, kind: MessageBannerKind.error),
                const SizedBox(height: 12),
              ],
              AppTextField(
                controller: _usernameCtrl,
                label: 'Username',
                hint: 'myusername',
                enabled: !_isLoading,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              _fieldHint('Unique identifier for this server', themeState),
              AppTextField(
                controller: _displayNameCtrl,
                label: 'Display Name',
                hint: 'My Display Name',
                enabled: !_isLoading,
                onChanged: (_) => setState(() {}),
              ),
              _fieldHint('How others will see you', themeState),
            ],
          ),
          actions: [
            AppButton(
              label: 'Later',
              variant: AppButtonVariant.secondary,
              onPressed: _isLoading ? null : _dismiss,
            ),
            AppButton(
              label: _isLoading ? 'Creating...' : 'Create Account',
              isLoading: _isLoading,
              onPressed: _canSubmit && !_isLoading ? _submit : null,
            ),
          ],
        );
      },
    );
  }

  Widget _fieldHint(String text, ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Text(
        text,
        style: AppText.label.copyWith(
          fontSize: 11,
          color: themeState.textQuaternary,
        ),
      ),
    );
  }
}
