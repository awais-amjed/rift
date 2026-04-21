import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_text_field.dart';
import '../../../theme/custom_colors.dart';

/// Form to join an existing server using a Supabase URL, invite code,
/// and a username / display name.
class JoinServerForm extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  const JoinServerForm({
    super.key,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<JoinServerForm> createState() => _JoinServerFormState();
}

class _JoinServerFormState extends State<JoinServerForm> {
  final _supabaseUrlCtrl = TextEditingController();
  final _inviteCodeCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _supabaseUrlCtrl.text.trim().isNotEmpty &&
      _inviteCodeCtrl.text.trim().isNotEmpty &&
      _usernameCtrl.text.trim().isNotEmpty &&
      _displayNameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _supabaseUrlCtrl.dispose();
    _inviteCodeCtrl.dispose();
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

    final supabaseUrl = _supabaseUrlCtrl.text.trim();
    final inviteCode = _inviteCodeCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final displayName = _displayNameCtrl.text.trim();

    // Register using cryptographic identity
    final result = await context.read<VaultCubit>().registerOnServer(
      supabaseUrl: supabaseUrl,
      inviteCode: inviteCode,
      username: username,
      displayName: displayName,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    // register now returns full server context — add directly
    final data = result.data!;
    final token = data['token'] as String;
    final serverCubit = context.read<ServerCubit>();
    serverCubit.addServer(supabaseUrl, token, data);

    if (!mounted) return;

    setState(() => _isLoading = false);

    HelperMethods.showSuccess(message: 'Joined server successfully!');
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) _ErrorBanner(message: _error!),

        AppTextField(
          controller: _supabaseUrlCtrl,
          label: 'Server URL',
          hint: 'https://xxxxx.supabase.co',
          enabled: !_isLoading,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _inviteCodeCtrl,
          label: 'Invite Code',
          hint: 'Paste the invite code you received',
          enabled: !_isLoading,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),

        AppTextField(
          controller: _usernameCtrl,
          label: 'Username',
          hint: 'myusername',
          enabled: !_isLoading,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _displayNameCtrl,
          label: 'Display Name',
          hint: 'How others will see you',
          enabled: !_isLoading,
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: _isLoading ? 'Joining...' : 'Join Server',
                onPressed: _canSubmit && !_isLoading ? _submit : null,
                isLoading: _isLoading,
                expanded: true,
              ),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: _isLoading ? null : widget.onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CustomColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CustomColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: CustomColors.error),
      ),
    );
  }
}
