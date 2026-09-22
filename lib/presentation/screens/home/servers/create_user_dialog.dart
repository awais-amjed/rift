import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/server_username.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/icon_tile.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

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
      ServerUsername.isValid(_usernameCtrl.text) &&
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
    final themeState = context.theme;
    return AppModal(
      title: 'Create your account',
      subtitle: 'Set up your profile for this server',
      // The rounded tile every other dialog opens with. It was a circle
      // here alone, which read as a different app's dialog.
      titleIcon: IconTile.title(
        icon: Icons.person_outline,
        color: themeState.primary,
      ),
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _usernameCtrl,
            label: 'Username',
            hint: 'myusername',
            enabled: !_isLoading,
            autofocus: true,
            // The mention parser's alphabet — see [ServerUsername].
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.-]')),
            ],
            maxLength: ServerUsername.maxLength,
            onChanged: (_) => setState(() {}),
          ),
          _fieldHint(ServerUsername.rule, themeState),
          AppTextField(
            controller: _displayNameCtrl,
            label: 'Display name',
            hint: 'My display name',
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
          label: _isLoading ? 'Creating...' : 'Create account',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
    );
  }

  Widget _fieldHint(String text, ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Text(
        text,
        style: AppText.label.copyWith(color: themeState.textTertiary),
      ),
    );
  }
}
